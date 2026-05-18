from rest_framework import viewsets, status, views
from rest_framework.decorators import action
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.authtoken.models import Token
from django.contrib.auth.models import User
from django.db.models import Sum, Q

from .models import Party, Entry, JewelleryItem, BusinessSetting, AuditLog
from .serializers import (
    PartySerializer, EntrySerializer,
    JewelleryItemSerializer, BusinessSettingSerializer,
)


# ─── Registration ────────────────────────────────────────────────────────────

class RegisterView(views.APIView):
    """
    Public endpoint. Creates a new user account and returns an auth token.
    POST /api/register/
    Body: { "username": "...", "password": "...", "email": "..." }
    """
    permission_classes = [AllowAny]

    def post(self, request):
        username = request.data.get('username', '').strip()
        password = request.data.get('password', '')
        email    = request.data.get('email', '').strip()

        # --- Validation ---
        if not username or not password:
            return Response(
                {'error': 'Username and password are required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if len(username) < 3:
            return Response(
                {'error': 'Username must be at least 3 characters.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if len(password) < 6:
            return Response(
                {'error': 'Password must be at least 6 characters.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if User.objects.filter(username__iexact=username).exists():
            return Response(
                {'error': 'Username already taken. Choose a different one.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if email and User.objects.filter(email__iexact=email).exists():
            return Response(
                {'error': 'An account with this email already exists.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # --- Create user ---
        user = User.objects.create_user(
            username=username,
            password=password,
            email=email,
        )
        token, _ = Token.objects.get_or_create(user=user)

        return Response(
            {'token': token.key, 'username': user.username},
            status=status.HTTP_201_CREATED,
        )


# ─── Business Settings ───────────────────────────────────────────────────────

class BusinessSettingView(views.APIView):
    def get(self, request):
        setting = BusinessSetting.load()
        serializer = BusinessSettingSerializer(setting)
        return Response(serializer.data)

    def put(self, request):
        if not request.user.is_superuser:
            return Response(
                {'error': 'Only owner can change settings.'},
                status=status.HTTP_403_FORBIDDEN,
            )
        setting = BusinessSetting.load()
        serializer = BusinessSettingSerializer(setting, data=request.data, partial=True)
        if serializer.is_valid():
            serializer.save()
            return Response(serializer.data)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


# ─── Parties ─────────────────────────────────────────────────────────────────

class PartyViewSet(viewsets.ModelViewSet):
    serializer_class = PartySerializer

    def get_queryset(self):
        """Only return parties owned by the current user."""
        queryset = Party.objects.filter(owner=self.request.user).order_by('-created_at')
        search = self.request.query_params.get('search')
        if search:
            queryset = queryset.filter(name__icontains=search)
        return queryset

    def perform_create(self, serializer):
        """Set the owner to the current user on creation."""
        serializer.save(owner=self.request.user)


# ─── Entries ─────────────────────────────────────────────────────────────────

class EntryViewSet(viewsets.ModelViewSet):
    serializer_class = EntrySerializer

    def get_queryset(self):
        """Only return entries whose party belongs to the current user."""
        queryset = Entry.objects.filter(
            party__owner=self.request.user
        ).order_by('-id')

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
            queryset = queryset.filter(
                Q(sr_number__icontains=search) | Q(party__name__icontains=search)
            )

        return queryset

    def destroy(self, request, *args, **kwargs):
        if not request.user.is_superuser:
            return Response(
                {'error': 'Only owner can delete entries.'},
                status=status.HTTP_403_FORBIDDEN,
            )
        return super().destroy(request, *args, **kwargs)

    def partial_update(self, request, *args, **kwargs):
        """
        PATCH with optimistic version locking.

        If the client sends a 'version' field:
          - client_version < server_version  → 409 Conflict (stale edit)
          - client_version == server_version → apply patch, bump version
          - no 'version' sent               → apply patch without bump (legacy clients)

        The Flutter app always sends 'version' in PATCH payloads (added to toJson()).
        """
        entry = self.get_object()  # already scoped to owner via get_queryset

        client_version_raw = request.data.get('version')
        if client_version_raw is not None:
            try:
                client_version = int(client_version_raw)
            except (ValueError, TypeError):
                client_version = None

            if client_version is not None and client_version < entry.version:
                return Response(
                    {
                        'conflict':       True,
                        'server_version': entry.version,
                        'client_version': client_version,
                        'entry_id':       entry.id,
                        'sr_number':      entry.sr_number,
                        'message': (
                            f'Version conflict on {entry.sr_number}: '
                            f'server is at version {entry.version}, '
                            f'your edit was based on version {client_version}. '
                            f'Another device may have edited this entry.'
                        ),
                    },
                    status=status.HTTP_409_CONFLICT,
                )

        # No conflict — apply the patch and increment version
        serializer = self.get_serializer(entry, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        # Bump version on every successful PATCH regardless of whether client sent it
        serializer.save(version=entry.version + 1)

        AuditLog.objects.create(
            entry=entry,
            action='EDIT',
            description=f'Entry {entry.sr_number} updated (version → {entry.version}).',
            actor=request.user.username,
        )

        return Response(serializer.data)

    @action(detail=False, methods=['get'])
    def stats(self, request):
        user_entries = Entry.objects.filter(party__owner=request.user)

        total_entries   = user_entries.exclude(status='DELETED').count()
        active_count    = user_entries.filter(status='ACTIVE').count()
        overdue_count   = user_entries.filter(status='OVERDUE').count()
        withdrawn_count = user_entries.filter(status='WITHDRAWN').count()
        closed_count    = user_entries.filter(status='CLOSED').count()
        total_parties   = Party.objects.filter(owner=request.user).count()

        active_amount  = user_entries.filter(status='ACTIVE').aggregate(
            total=Sum('amount'))['total'] or 0
        overdue_amount = user_entries.filter(status='OVERDUE').aggregate(
            total=Sum('amount'))['total'] or 0

        return Response({
            'total_entries':  total_entries,
            'active':         active_count,
            'overdue':        overdue_count,
            'withdrawn':      withdrawn_count,
            'closed':         closed_count,
            'total_parties':  total_parties,
            'active_amount':  float(active_amount),
            'overdue_amount': float(overdue_amount),
        })

    @action(detail=True, methods=['post'])
    def withdraw(self, request, pk=None):
        from datetime import date as dt
        entry = self.get_object()  # already scoped to user via get_queryset

        if entry.status not in ['ACTIVE', 'OVERDUE']:
            return Response(
                {'error': 'Only ACTIVE or OVERDUE entries can be withdrawn.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        entry.status    = 'WITHDRAWN'
        entry.closed_at = dt.today()
        entry.save()

        AuditLog.objects.create(
            entry=entry,
            action='WITHDRAW',
            description=(
                f"Entry {entry.sr_number} for {entry.party.name} withdrawn. "
                f"Total settled: ₹{entry.total_payable}"
            ),
            actor=request.user.username,
        )

        return Response(self.get_serializer(entry).data)

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

        AuditLog.objects.create(
            entry=entry,
            action='OVERDUE',
            description=f"Entry {entry.sr_number} for {entry.party.name} marked as overdue.",
            actor=request.user.username,
        )
        return Response(self.get_serializer(entry).data)


# ─── Jewellery Items ─────────────────────────────────────────────────────────

class JewelleryItemViewSet(viewsets.ModelViewSet):
    serializer_class = JewelleryItemSerializer

    def get_queryset(self):
        """Only return items whose entry belongs to a party owned by the current user."""
        queryset = JewelleryItem.objects.filter(
            entry__party__owner=self.request.user
        )
        entry_id = self.request.query_params.get('entry')
        if entry_id:
            queryset = queryset.filter(entry_id=entry_id)
        return queryset