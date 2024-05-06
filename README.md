# Airflow on Minikube


## Introduction

This guide outlines the steps to set up Apache Airflow on a local Kubernetes cluster using [Minikube](https://minikube.sigs.k8s.io/docs/) a user-friendly and lightweight Kubernetes implementation. 

It addresses a gap in existing tutorials, which primarily focus on [Kind](https://kind.sigs.k8s.io) as the local Kubernetes cluster tool. Additionally, this project explores utilising the local filesystem for DAG storage, offering an alternative to the commonly used Git-based approach.

The key benefits of this project:

- **Simplified Local Development:** Minikube, a user-friendly and lightweight Kubernetes implementation, simplifies the setup process and provides easy options for mounting drives, creating port-forwarding and providing a container registry.
- **Flexibility with Local Filesystem:** This guide delves into using the local filesystem for DAG storage. This empowers developers to manage DAGs locally on their machines without relying solely on Git-based workflows. It provides an alternative to the git sync option, giving developers the flexibility to choose between the two approaches.
- **Enhanced Understanding:** This guide aims to contribute to the developer knowledge base by addressing gaps and methods that are less commonly discussed in most online tutorials.
- **Ephemerality / Transient Development Environment:** The project is designed with a development mindset, encouraging experimentation and learning from mistakes. It takes away the burden of having to do complex configurations, allowing the developer to rebuild the cluster quickly with a single [command](https://www.notion.so/Airflow-on-Minikube-af082d65d9f64bed95017bb1aebd0d53?pvs=21). Remember, if you're not making some mistakes while experimenting, you might not be pushing your learning boundaries enough! 🙂

By addressing the under-represented area of Minikube and Airflow development and exploring the local filesystem approach, this project empowers developers seeking to experiment with alternative workflows for DAG storage beyond Git and gain practical experience with key concepts like persistent volumes, persistent volume claims, and networking in Kubernetes.

## Switch to bash and Activate a Python environment

If you are using conda you can use `conda activate <<env>>` in my case I will use the base environment.

```bash
# Depending on your OS and environment activate a conda environment
/bin/bash
# Ensure the conda init is already run and a .bash_profile is present
conda init
# The source command is used for instances where you bash is not initialised
source ~/.bash_profile
# Then choose the base environment, as we only need a basic python functionality
conda activate base
```

<aside>
💡 **Optional:** Once the base environment is activated, create a new virtual environment to install the airflow dependencies necessary for writing python that references the airflow libraries. This step is optional if your conda environment already has the airflow requirements.

</aside>

## Create a Minikube Cluster

```bash
export CLUSTERNAME="project-matrix"
export PROJECT_HOME='/Users/jeanboutros/Projects/DataProjects/Airflow'
# export PROJECT_HOME='/home/hu/DataProjects/Airflow'

minikube start --driver=docker --memory='max' \
	--cpus=all --network-plugin=cni --cni=calico \ 
	--kubernetes-version=v1.30.0 \ 
	-p $CLUSTERNAME \ 
	--mount --mount-string="$PROJECT_HOME/data:/mnt/data"

# sets the current minikube profile
minikube profile $CLUSTERNAME

# point the shell to minikube's docker-daemon
minikube docker-env
eval $(minikube -p $CLUSTERNAME docker-env)
```

## Create the Project Directory

```bash
# Create the directory for this project
mkdir DataProjects
mkdir DataProjects/Airflow
cd ./DataProjects/Airflow/
```

## Create a Namespace for Airflow

```bash
kubectl create namespace airflow
```

## Setup the Airflow configurations files

```docker
# Add the helm repo of airflow
# https://airflow.apache.org/docs/helm-chart/stable/index.html#installing-the-chart
helm repo add apache-airflow https://airflow.apache.org

# Create the file .\DataProjects\Airflow\airflow_helm_value.yaml
touch airflow_helm_values.yaml

# Check the default values of the helm configurations
helm show values apache-airflow/airflow > .\airflow_helm_values_full.yaml
code .\airflow_helm_values_full.yaml
```

Add inside airflow_helm_values.yaml the following values:

```bash
# Default airflow repository -- overridden by all the specific images below
defaultAirflowRepository: airflow-custom-image

# Default airflow tag to deploy
defaultAirflowTag: "0.0.1"

# Airflow version (Used to make some decisions based on Airflow Version being deployed)
airflowVersion: "2.9.0"

webserverSecretKeySecretName: my-webserver-secret

dags:
  # Where dags volume will be mounted. Works for both persistence and gitSync.
  # If not specified, dags mount path will be set to $AIRFLOW_HOME/dags
  mountPath: ~
  persistence:
    # Enable persistent volume for storing dags
    enabled: true
    # Volume size for dags
    size: 10Gi
    # access mode of the persistent volume
    accessMode: ReadWriteOnce
    ## the name of an existing PVC to use
    existingClaim: dag-pv-claim

# Note for Rancher users
# When installing the chart using Argo CD, Flux, Rancher or Terraform, 
# MUST set the four following values, or the application will not 
# start as the migrations will not be run.
# https://airflow.apache.org/docs/helm-chart/stable/index.html#installing-the-chart-with-argo-cd-flux-rancher-or-terraform
#
# Note for the webserver key
# We should set a static webserver secret key when deploying with this chart as it 
# will help ensure your Airflow components only restart when necessary.
# https://airflow.apache.org/docs/helm-chart/stable/production-guide.html#webserver-secret-key
createUserJob:
  useHelmHooks: false
  applyCustomEnv: false
migrateDatabaseJob:
  useHelmHooks: false
  applyCustomEnv: false
```

## Create a Secret for the Airflow web server

```bash
# Create the secret for the airflow web server
kubectl create secret generic my-webserver-secret --from-literal="webserver-secret-key=$(python -c 'import secrets; print(secrets.token_hex(16))')" --namespace airflow
```

## Create a Persistent Volume and a Claim

### Configure Airflow to use a Persistent Volume for DAGs

I chose not to go the `gitSync` route for two reasons, mainly because I couldn’t find many tutorials that explain how to use it, but also because I want to create a local development environment without depending on a git repository.

```bash
touch dag-pv-volume.yaml
touch dag-pv-claim.yaml
```

The PV YAML:

```yaml

apiVersion: v1
kind: PersistentVolume
metadata:
  name: dag-pv-volume
  namespace: airflow
  labels:
    type: local-volume
    content: airflow-dags
spec:
  storageClassName: manual
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  volumeMode: Filesystem
  # https://kubernetes.io/docs/tasks/configure-pod-container/configure-persistent-volume-storage/#create-a-persistentvolume
  # In a production cluster, you would not use hostPath. 
  # Instead a cluster administrator would provision a network resource 
  # like a Google Compute Engine persistent disk, an NFS share, or an Amazon Elastic Block Store volume.
  hostPath:
    path: "/airflow/dags"
```

The PVC YAML:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dag-pv-claim
  namespace: airflow
  labels:
    type: volume-claim
    content: airflow-dags
spec:
  storageClassName: manual
  accessModes:
    # Maybe ReadOnlyMany is a better option but it's something to investigate further.
    - ReadWriteOnce
  volumeMode: Filesystem
  resources:
    requests:
      storage: 10Gi
  selector:
    matchLabels:
      type: local-volume
      content: airflow-dags

```

Create the PV and PVC:

```bash
kubectl apply -f dag-pv-volume.yaml
kubectl apply -f dag-pv-claim.yaml

# kubectl get pv dag-pv-volume -n airflow
kubectl get pvc dag-pv-claim -n airflow
```

### Mount a volume in Minikube

Now the most important command:

```bash
minikube mount $PROJECT_HOME/data/dags:/airflow/dags
```

Further references:

[Manage DAGs files — helm-chart Documentation](https://airflow.apache.org/docs/helm-chart/stable/manage-dags-files.html#mounting-dags-from-an-externally-populated-pvc)

[Configure a Pod to Use a PersistentVolume for Storage](https://kubernetes.io/docs/tasks/configure-pod-container/configure-persistent-volume-storage/#create-a-persistentvolume)

[Mounting filesystems](https://minikube.sigs.k8s.io/docs/handbook/mount/)

## Create the first DAG to test it out

Call the file [dag1.py](http://dag1.py) and store it in the directory ./dags/ inside our project folder.

```python
from airflow.models.dag import DAG
from datetime import datetime

with DAG("d1", 
         description="",
         schedule_interval="@daily",
         start_date=datetime(2024,1,1),
         catchup=False):
    pass
```

## Building a Custom Airflow Image

The purpose is to build an airflow image that contains our custom dependencies, in this case the ClickHouse database dependencies.

Create a folder called `airflow-custom-image` and put inside it the following files.

Create a `requirements.txt`

```python
clickhouse-driver==0.2.7
airflow-clickhouse-plugin[common.sql]==1.3.0
```

Create a custom `Dockerfile`

```docker
# syntax=docker/dockerfile:1
FROM apache/airflow:2.9.0

COPY ./requirements.txt ~/
RUN python -m pip install --upgrade pip
RUN pip install -r requirements.txt
```

Now create the docker image inside our Minikube cluster’s docker registry.

```bash
# Move inside the directory holding our requirements.txt file and 
# our Dockerfile
cd airflow-custom-image

# Run the eval again to insure the instance of the open terminal
# is referring to the docker inside the minikube cluster
eval $(minikube docker-env)

# Build the image
docker build -t airflow-custom-image:0.0.1 . 

# List the images to verify that it's present
docker image list

# Return to the Project folder
cd ..
```

The docker image list command should return a list of images including the newly created one.

![Screenshot 2024-05-02 at 14.00.06.png](Airflow%20on%20Minikube%20af082d65d9f64bed95017bb1aebd0d53/Screenshot_2024-05-02_at_14.00.06.png)

References:

[Pushing images](https://minikube.sigs.k8s.io/docs/handbook/pushing/)

# Install Airflow using Helm

The installation will use the custom Helm configuration values that we edited and consequently will us our custom airflow image for the installation.

```bash

# Install Airflow using helm, with the custom configurations
helm upgrade --install airflow apache-airflow/airflow --namespace airflow --create-namespace -f ./airflow_helm_values.yaml --debug

# Check that the pods are running
kubectl get pods --namespace airflow
```

## Setup port forwarding

To be able to access airflow web server we need to set up port forwarding and forward the web server’s 8080 port to a port of our choice. I’ll stick to 8080 on my end.

```bash
kubectl port-forward svc/airflow-webserver 8080:8080 --namespace airflow
```

At this point Airflow should be up and running on [http://localhost:8080/](http://localhost:8080/) with username and password set to **admin**.


## Create a DAG for Airflow

Create a dag and name it `my-first-dag.py` then place it in the project directory under `./data/dags`

```python
from airflow.models.dag import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.postgres.operators.postgres import SQLExecuteQueryOperator
from datetime import datetime

import logging
logger = logging.getLogger(__name__)


with DAG("my-first-dag", 
         description="",
         schedule="@daily",
         start_date=datetime(2024,1,1),
         catchup=False):
    
    t1 = SQLExecuteQueryOperator(task_id='setup_postgresql_test_table', 
                                 autocommit=True,
                                database='hello_airflow_world',
                                conn_id='postgres_connection',
                       sql=(               
                          '''
                          CREATE TABLE IF NOT EXISTS replicated_table
                          (
                              id serial primary key,
                              text_column1 bpchar not null,
                              text_column2 bpchar not null
                          );
                          '''
                       ),
                       
                       )
    
    t2 = SQLExecuteQueryOperator(task_id='insert_trash_into_table', 
                                 autocommit=True,
                                database='hello_airflow_world',
                                conn_id='postgres_connection',
                       sql=(               
                          '''
                          INSERT INTO replicated_table (text_column1, text_column2) 
                          VALUES ('test', now()::bpchar);
                          '''
                       ),
                       )
    

    

    t3 = PythonOperator(task_id='get_db_creation_result',
                         python_callable=lambda task_instance: logger.info(task_instance.xcom_pull(task_ids='insert_trash_into_table')),
                         )
    
    t1 >> t2 >> t3
    
```

# Create a Connection in Airflow for ClickHouse

```bash
Connection ID: clickhouse_connection
Connection Type: SQLite
Hostname: clickhouse.clickhouse.svc.cluster.local
Port: 9000
Username: admin
Password: admin
```

References:

[DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)

## Network Isolation and Zero Trust

 While this guide focuses primarily on the core functionalities of deploying Airflow with Minikube, it's crucial to emphasize the importance of robust network security practices, particularly the principles of zero-trust.  Zero-trust dictates that no component within a system should be implicitly trusted and all communication channels must be explicitly authorized.

 ### Ingress and Egress Network Policies

 To achieve zero-trust principles, implementing proper network policies is essential. These policies control both inbound (ingress) and outbound (egress) traffic between different components in a Kubernetes cluster. By carefully defining these policies, we can restrict communication only to authorized sources and destinations, significantly reducing the attack surface and potential security vulnerabilities.

 The following video offers an interesting starting point to understand how these policies work in practice:
[Mastering Namespace Isolation in Kubernetes with Calico Policies](https://www.youtube.com/watch?v=-Hzt1YcjQZk)

## PostgreSQL Installation

Create a YAML file with the custom configuration for PostgreSQL.

```yaml
global:
  postgresql:
    auth:
      username: "admin"
      password: "admin"
      database: "test-db"

auth:
  postgresPassword: "admin"

architecture: replication

replication:
  synchronousCommit: "on"
  numSynchronousReplicas: 2
  applicationName: "pg-replication-app"

primary:
  name: "main"

readReplicas:
  name: "replica"
  replicaCount: 2
```

Run the following command to install the database with two replicas:

```bash
helm upgrade --install postgresql oci://registry-1.docker.io/bitnamicharts/postgresql -f pg-helm-values.yaml -n pg --create-namespace
```

PostgreSQL installation should return the following:

```
PostgreSQL can be accessed via port 5432 on the following DNS names from within your cluster:

    postgresql-main.pg.svc.cluster.local - Read/Write connection

    postgresql-replica.pg.svc.cluster.local - Read only connection

To get the password for "postgres" run:

    export POSTGRES_ADMIN_PASSWORD=$(kubectl get secret --namespace pg postgresql -o jsonpath="{.data.postgres-password}" | base64 -d)

To get the password for "admin" run:

    export POSTGRES_PASSWORD=$(kubectl get secret --namespace pg postgresql -o jsonpath="{.data.password}" | base64 -d)

To connect to your database run the following command:

    kubectl run postgresql-client --rm --tty -i --restart='Never' --namespace pg --image docker.io/bitnami/postgresql:16.2.0-debian-12-r18 --env="PGPASSWORD=$POSTGRES_PASSWORD" \
      --command -- psql --host postgresql-main -U admin -d test-db -p 5432

    > NOTE: If you access the container using bash, make sure that you execute "/opt/bitnami/scripts/postgresql/entrypoint.sh /bin/bash" in order to avoid the error "psql: local user with ID 1001} does not exist"

To connect to your database from outside the cluster execute the following commands:

    kubectl port-forward --namespace pg svc/postgresql-main 5432:5432 &
    PGPASSWORD="$POSTGRES_PASSWORD" psql --host 127.0.0.1 -U admin -d test-db -p 5432

WARNING: The configured password will be ignored on new installation in case when previous PostgreSQL release was deleted through the helm command. In that case, old PVC will have an old password, and setting it through helm won't take effect. Deleting persistent volumes (PVs) will solve the issue.

WARNING: There are "resources" sections in the chart not set. Using "resourcesPreset" is not recommended for production. For production installations, please set the following values according to your workload needs:
  - primary.resources
  - readReplicas.resources
+info https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/

```