from django.db import models
from django.utils import timezone
from django.conf import settings
from django.core.mail import send_mail 
import random
from .tasks import send_async_email

# --- CUSTOM ID GENERATOR ---
def generate_tracking_id():
    """Generates a random 10-digit number prefixed with DEV"""
    number = random.randint(1000000000, 9999999999)
    return f"DEV{number}"

# --- DATABASE MODELS ---
class Facility(models.Model):
    name = models.CharField(max_length=100)
    latitude = models.FloatField()
    longitude = models.FloatField()

    def __str__(self):
        return self.name
    
class Shipment(models.Model):
    tracking_id = models.CharField(max_length=50, unique=True, default=generate_tracking_id)
    origin = models.CharField(max_length=255)
    destination = models.CharField(max_length=255)
    customer_email = models.EmailField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    total_distance = models.FloatField(default=0.0)

    def __str__(self):
        return str(self.tracking_id)
    
class Waypoint(models.Model):
    shipment = models.ForeignKey(Shipment, on_delete=models.CASCADE, related_name='waypoints')
    location_name = models.CharField(max_length=255)
    latitude = models.FloatField()
    longitude = models.FloatField()
    stop_number = models.IntegerField()
    status = models.CharField(
        max_length=20, 
        choices=[('PENDING', 'Pending'), ('COMPLETED', 'Completed')],
        default='PENDING'
    )

    class Meta:
        ordering = ['stop_number']
                                  
class TrackingEvent(models.Model):
    shipment = models.ForeignKey(Shipment, on_delete=models.CASCADE, related_name='events')
    timestamp = models.DateTimeField(default=timezone.now)
    location = models.CharField(max_length=255)
    status = models.CharField(max_length=50, default="IN_TRANSIT")
    description = models.CharField(max_length=255)

    class Meta:
        ordering = ['-timestamp']
        
class SupportTicket(models.Model):
    shipment = models.ForeignKey(Shipment, on_delete=models.CASCADE, related_name='tickets')
    customer_email = models.EmailField()
    customer_message = models.TextField()
    admin_reply = models.TextField(blank=True, null=True, help_text="Type your reply here. It will automatically email the customer.")
    created_at = models.DateTimeField(auto_now_add=True)
    is_resolved = models.BooleanField(default=False)

    def save(self, *args, **kwargs):
        is_new_ticket = self.pk is None
        
        # Check if the admin just typed a reply
        admin_just_replied = False
        if not is_new_ticket:
            old_ticket = SupportTicket.objects.get(pk=self.pk)
            if self.admin_reply and not old_ticket.admin_reply:
                admin_just_replied = True

        super().save(*args, **kwargs)

        # TRIGGER 1: Customer creates a new ticket -> Email Admin via Celery
        if is_new_ticket:
            
            send_async_email.delay(
                subject=f"URGENT: New Support Ticket for {self.shipment.tracking_id}",
                message=f"A customer has requested support.\n\nTracking ID: {self.shipment.tracking_id}\nCustomer: {self.customer_email}\nMessage: {self.customer_message}\n\nLog in to the admin panel to reply.",
                recipient_list=['admin@yourlogistics.com']
            )

        # TRIGGER 2: Admin writes a reply -> Email Customer via Celery
        if admin_just_replied:
            
            send_async_email.delay(
                subject=f"Update on your shipment: {self.shipment.tracking_id}",
                message=f"Hello,\n\nOur support team has replied to your inquiry regarding tracking ID {self.shipment.tracking_id}:\n\nAdmin Reply: {self.admin_reply}\n\nOriginal Message: {self.customer_message}",
                recipient_list=[self.customer_email]
            )
            
            # Auto-resolve the ticket to keep the dashboard clean
            SupportTicket.objects.filter(pk=self.pk).update(is_resolved=True)

    def __str__(self):
        return f"Ticket for {self.shipment.tracking_id} - Resolved: {self.is_resolved}"
    

class ContactMessage(models.Model):
    SERVICE_CHOICES = [
        ('International Express', 'International Express'),
        ('Ocean Freight', 'Ocean Freight'),
        ('Road Freight', 'Road Freight'),
        ('Warehousing & Fulfillment', 'Warehousing & Fulfillment'),
        ('Customs Clearance', 'Customs Clearance'),
        ('General Enquiry', 'General Enquiry'),
        ('Track a Shipment', 'Track a Shipment'),
    ]

    first_name = models.CharField(max_length=100)
    last_name = models.CharField(max_length=100)
    email = models.EmailField()
    phone_number = models.CharField(max_length=20, blank=True, null=True)
    service_enquiry = models.CharField(max_length=50, choices=SERVICE_CHOICES)
    origin_country = models.CharField(max_length=100, blank=True, null=True)
    destination_country = models.CharField(max_length=100, blank=True, null=True)
    message = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)
    is_resolved = models.BooleanField(default=False)

    def __str__(self):
        return f"{self.first_name} {self.last_name} - {self.service_enquiry}"