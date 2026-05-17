from django.urls import path
from rest_framework.routers import DefaultRouter
from .views import *


router = DefaultRouter()

router.register('parties', PartyViewSet)
router.register('entries', EntryViewSet)
router.register('items', JewelleryItemViewSet)

urlpatterns = [
    path('settings/', BusinessSettingView.as_view(), name='business-settings'),
] + router.urls