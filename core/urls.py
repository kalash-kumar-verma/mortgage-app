from django.urls import path
from rest_framework.routers import DefaultRouter
from .views import (
    PartyViewSet, EntryViewSet, JewelleryItemViewSet, 
    BusinessSettingView, RegisterView, UserProfileView, 
    LogoutAllDevicesView, PartialPaymentViewSet, ActivityLogViewSet
)

router = DefaultRouter()
router.register('parties', PartyViewSet, basename='party')
router.register('entries', EntryViewSet, basename='entry')
router.register('items',   JewelleryItemViewSet, basename='item')
router.register('payments', PartialPaymentViewSet, basename='payment')
router.register('activities', ActivityLogViewSet, basename='activity')

urlpatterns = [
    path('settings/', BusinessSettingView.as_view(), name='business-settings'),
    path('register/', RegisterView.as_view(), name='register'),
    path('auth/logout_all/', LogoutAllDevicesView.as_view(), name='logout-all'),
    path('profile/', UserProfileView.as_view(), name='user-profile'),
] + router.urls