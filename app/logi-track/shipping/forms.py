from django import forms
from .models import ContactMessage

class ContactMessageForm(forms.ModelForm):
    class Meta:
        model = ContactMessage
        fields = [
            'first_name', 'last_name', 'email', 'phone_number', 
            'service_enquiry', 'origin_country', 'destination_country', 'message'
        ]