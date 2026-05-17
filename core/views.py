from rest_framework import viewsets, status, views
from rest_framework.decorators import action
from rest_framework.response import Response
from django.db.models import Sum

from .models import Party, Entry, JewelleryItem, BusinessSetting, AuditLog
from .serializers import PartySerializer, EntrySerializer, JewelleryItemSerializer, BusinessSettingSerializer


class BusinessSettingView(views.APIView):
    def get(self, request):
        setting = BusinessSetting.load()
        serializer = BusinessSettingSerializer(setting)
        return Response(serializer.data)

    def put(self, request):
        if not request.user.is_superuser:
            return Response({'error': 'Only owner can change settings.'}, status=status.HTTP_403_FORBIDDEN)
        setting = BusinessSetting.load()
        serializer = BusinessSettingSerializer(setting, data=request.data, partial=True)
        if serializer.is_valid():
            serializer.save()
            return Response(serializer.data)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class PartyViewSet(viewsets.ModelViewSet):
    queryset = Party.objects.all()
    serializer_class = PartySerializer

    def get_queryset(self):
        queryset = Party.objects.all().order_by('-created_at')
        search = self.request.query_params.get('search')
        if search:
            queryset = queryset.filter(name__icontains=search)
        return queryset


class EntryViewSet(viewsets.ModelViewSet):
    queryset = Entry.objects.all()
    serializer_class = EntrySerializer

    def get_queryset(self):
        queryset = Entry.objects.all().order_by('-id')

    def destroy(self, request, *args, **kwargs):
        if not request.user.is_superuser:
            return Response({'error': 'Only owner can delete entries.'}, status=status.HTTP_403_FORBIDDEN)
        return super().destroy(request, *args, **kwargs)

        include_deleted = self.request.query_params.get('include_deleted')
        if not include_deleted:
            queryset = queryset.exclude(status='DELETED')

        party_id = self.request.query_params.get('party')
        if party_id:
            queryset = queryset.filter(party_id=party_id)

        status_filter = self.request.query_params.get('status')
        if status_filter:
            queryset = queryset.filter(status=status_filter)

        search = self.request.query_params.get('search')
        if search:
            queryset = queryset.filter(sr_number__icontains=search)

        return queryset

    @action(detail=False, methods=['get'])
    def stats(self, request):
        total_entries = Entry.objects.exclude(status='DELETED').count()
        active_count = Entry.objects.filter(status='ACTIVE').count()
        overdue_count = Entry.objects.filter(status='OVERDUE').count()
        withdrawn_count = Entry.objects.filter(status='WITHDRAWN').count()
        closed_count = Entry.objects.filter(status='CLOSED').count()
        total_parties = Party.objects.count()

        active_amount = Entry.objects.filter(
            status='ACTIVE'
        ).aggregate(total=Sum('amount'))['total'] or 0

        overdue_amount = Entry.objects.filter(
            status='OVERDUE'
        ).aggregate(total=Sum('amount'))['total'] or 0

        return Response({
            'total_entries': total_entries,
            'active': active_count,
            'overdue': overdue_count,
            'withdrawn': withdrawn_count,
            'closed': closed_count,
            'total_parties': total_parties,
            'active_amount': float(active_amount),
            'overdue_amount': float(overdue_amount),
        })

    @action(detail=True, methods=['post'])
    def withdraw(self, request, pk=None):
        from datetime import date as dt
        entry = self.get_object()

        if entry.status not in ['ACTIVE', 'OVERDUE']:
            return Response(
                {'error': 'Only ACTIVE or OVERDUE entries can be withdrawn.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        entry.status = 'WITHDRAWN'
        entry.closed_at = dt.today()
        entry.save()
        
        # Write Audit Log
        AuditLog.objects.create(
            entry=entry,
            action='WITHDRAW',
            description=f"Entry {entry.sr_number} for {entry.party.name} withdrawn. Total settled: ₹{entry.total_payable}",
            actor=request.user.username
        )

        serializer = self.get_serializer(entry)
        return Response(serializer.data)

    @action(detail=True, methods=['post'])
    def mark_overdue(self, request, pk=None):
        entry = self.get_object()
        if entry.status != 'ACTIVE':
            return Response(
                {'error': 'Only ACTIVE entries can be marked overdue.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        entry.status = 'OVERDUE'
        entry.save()
        
        # Write Audit Log
        AuditLog.objects.create(
            entry=entry,
            action='OVERDUE',
            description=f"Entry {entry.sr_number} for {entry.party.name} marked as overdue.",
            actor=request.user.username
        )
        serializer = self.get_serializer(entry)
        return Response(serializer.data)


class JewelleryItemViewSet(viewsets.ModelViewSet):
    queryset = JewelleryItem.objects.all()
    serializer_class = JewelleryItemSerializer

    def get_queryset(self):
        queryset = JewelleryItem.objects.all()
        entry_id = self.request.query_params.get('entry')
        if entry_id:
            queryset = queryset.filter(entry_id=entry_id)
        return queryset