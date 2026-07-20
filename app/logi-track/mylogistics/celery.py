import os
from celery import Celery, shared_task
import time


# Set the default Django settings module for the 'celery' program.
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'mylogistics.settings')

app = Celery('mylogistics')

# Load task modules from all registered Django apps.
app.config_from_object('django.conf:settings', namespace='CELERY')
app.autodiscover_tasks()

@shared_task
def simulate_heavy_lifting():
    print("Starting background job: Processing tracking update...")
    time.sleep(5) # Simulates a task taking 5 seconds
    print("Background job finished! Email sent.")
    return "Task Complete"