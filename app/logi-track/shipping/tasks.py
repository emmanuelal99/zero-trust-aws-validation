from celery import shared_task
from django.core.mail import send_mail
from django.conf import settings

@shared_task
def send_async_email(subject, message, recipient_list):
    """
    This function gets pushed to the Redis queue and is 
    executed in the background by Celery workers.
    """
    send_mail(
        subject=subject,
        message=message,
        from_email=settings.DEFAULT_FROM_EMAIL,
        recipient_list=recipient_list,
        fail_silently=False,
    )
    return f"Email successfully sent to {recipient_list}"