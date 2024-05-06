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
