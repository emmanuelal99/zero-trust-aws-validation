from django.urls import path
from .views import homepage, tracking_page, ScannerUpdateAPI, about_page, contact_page, service_page, submit_support_ticket

urlpatterns = [
    # This catches the empty string and loads the homepage search bar
    path('', homepage, name='homepage'),
    path('about/', about_page, name='about_page'),
    path('contact/', contact_page, name='contact_page'),
    path('services/', service_page, name='service_page'),
    path('track/<str:tracking_id>/', tracking_page, name='tracking_page'),
    path('api/scanner/', ScannerUpdateAPI.as_view(), name='scanner_api'),
    path('ticket/<str:tracking_id>/', submit_support_ticket, name='submit_ticket'),


]