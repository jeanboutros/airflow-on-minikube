os="$(uname -o)"

export PROJECT_NAME="project-matrix"
export PROJECT_HOME='/home/hu/DataProjects/Airflow'
# When working on my mac, change the project home.
if [[ $os == "Darwin" ]]; then export PROJECT_HOME='/Users/jeanboutros/Projects/DataProjects/Airflow'; fi;

cd $PROJECT_HOME

echo "✅ PROJECT_NAME is set to '$PROJECT_NAME'"
echo "✅ PROJECT_HOME is set to '$PROJECT_HOME'"

echo "🗑️ Stopping and removing any previous instance of '$PROJECT_NAME'"
minikube stop -p $PROJECT_NAME
minikube delete -p $PROJECT_NAME

echo "⚙️ Creating a Minikube instance for project '$PROJECT_NAME'"


mount_arg='--mount --mount-string="$PROJECT_HOME/data:/mnt/data"'
if [[ $os == "Darwin" ]]; then export mount_arg=''; fi;


minikube start --driver=docker --memory='max' \
	--cpus=all --network-plugin=cni --cni=calico \
	--kubernetes-version=v1.30.0 \
	-p $PROJECT_NAME $mount_arg


echo "📌 Selecting '$PROJECT_NAME' as the current Minikube profile"

# sets the current minikube profile
minikube profile $PROJECT_NAME

echo "🚽 Configuring the docker env."

# point the shell to minikube's docker-daemon
eval $(minikube -p $PROJECT_NAME docker-env)

echo "👋🏻✌🏻 Done."


# #### AIRFLOW HELM PREP #### # 

# Add the helm repo of airflow
# https://airflow.apache.org/docs/helm-chart/stable/index.html#installing-the-chart
helm repo add apache-airflow https://airflow.apache.org

# Create the file .\DataProjects\Airflow\airflow_helm_value.yaml
# touch airflow_helm_values.yaml

# Check the default values of the helm configurations
helm show values apache-airflow/airflow > .\airflow_helm_values_full.yaml



# #### AIRFLOW DOCKER IMAGE PREP #### # 
# Move inside the directory holding our requirements.txt file and 
# our Dockerfile
cd airflow-custom-image

# Run the eval again to insure the instance of the open terminal
# is referring to the docker inside the minikube cluster
eval $(minikube docker-env)

# Build the image
docker build -t airflow-custom-image:0.0.1 . 

# Return to the Project folder
cd ..



# #### AIRFLOW K8S PREP #### # 
kubectl create namespace airflow
# Create the secret for the airflow web server
kubectl create secret generic my-webserver-secret --from-literal="webserver-secret-key=$(python -c 'import secrets; print(secrets.token_hex(16))')" --namespace airflow

kubectl apply -f dag-pv-volume.yaml
kubectl apply -f dag-pv-claim.yaml


# Install Airflow using helm, with the custom configurations
helm upgrade --install airflow apache-airflow/airflow --namespace airflow --create-namespace -f airflow_helm_values.yaml --debug
# Install PostgreSQL using helm, with the custom configurations
helm upgrade --install postgresql oci://registry-1.docker.io/bitnamicharts/postgresql -f postgresql-helm-values.yaml -n pg --create-namespace



echo "Consider executing:"
echo "kubectl port-forward svc/airflow-webserver 8080:8080 --namespace airflow"
echo "If you are on a macOS consider executing:"
echo "minikube mount $PROJECT_HOME/data/dags:/airflow/dags&"

