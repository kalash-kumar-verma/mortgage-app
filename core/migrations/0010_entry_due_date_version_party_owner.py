from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


def assign_existing_parties_to_superuser(apps, schema_editor):
    """Data migration: assign all existing ownerless parties to the first superuser."""
    User = apps.get_model('auth', 'User')
    Party = apps.get_model('core', 'Party')
    superuser = User.objects.filter(is_superuser=True).first()
    if superuser:
        updated = Party.objects.filter(owner=None).update(owner=superuser)
        print(f'\n[Migration] Assigned {updated} existing parties to superuser: {superuser.username}')
    else:
        print('\n[Migration] WARNING: No superuser found. Existing parties have no owner. Create one with: python manage.py createsuperuser')


def reverse_assign(apps, schema_editor):
    """Reverse: set all owners back to None."""
    Party = apps.get_model('core', 'Party')
    Party.objects.all().update(owner=None)


class Migration(migrations.Migration):

    dependencies = [
        ('core', '0009_alter_entry_sr_number'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        # 1. Add nullable due_date to Entry
        migrations.AddField(
            model_name='entry',
            name='due_date',
            field=models.DateField(blank=True, null=True),
        ),
        # 2. Add version to Entry (default=1, for conflict detection)
        migrations.AddField(
            model_name='entry',
            name='version',
            field=models.IntegerField(default=1),
        ),
        # 3. Add nullable owner FK to Party
        migrations.AddField(
            model_name='party',
            name='owner',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.CASCADE,
                related_name='parties',
                to=settings.AUTH_USER_MODEL,
            ),
        ),
        # 4. Data migration: assign existing parties to superuser
        migrations.RunPython(
            assign_existing_parties_to_superuser,
            reverse_code=reverse_assign,
        ),
    ]
