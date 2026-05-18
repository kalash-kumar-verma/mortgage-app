from django.urls import path
from rest_framework.routers import DefaultRouter
from .views import PartyViewSet, EntryViewSet, JewelleryItemViewSet, BusinessSettingView, RegisterView

router = DefaultRouter()
router.register('parties', PartyViewSet, basename='party')
router.register('entries', EntryViewSet, basename='entry')
router.register('items',   JewelleryItemViewSet, basename='item')

urlpatterns = [
    path('settings/', BusinessSettingView.as_view(), name='business-settings'),
    path('register/', RegisterView.as_view(), name='register'),
] + router.urls