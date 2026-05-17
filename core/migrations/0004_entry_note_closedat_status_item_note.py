from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('core', '0003_alter_entry_sr_number'),
    ]

    operations = [
        migrations.AddField(
            model_name='entry',
            name='note',
            field=models.TextField(blank=True, default=''),
        ),
        migrations.AddField(
            model_name='entry',
            name='closed_at',
            field=models.DateField(blank=True, null=True),
        ),
        migrations.AlterField(
            model_name='entry',
            name='status',
            field=models.CharField(
                choices=[
                    ('ACTIVE', 'Active'),
                    ('OVERDUE', 'Overdue'),
                    ('WITHDRAWN', 'Withdrawn'),
                    ('CLOSED', 'Closed'),
                    ('DELETED', 'Deleted'),
                ],
                default='ACTIVE',
                max_length=20,
            ),
        ),
        migrations.AddField(
            model_name='jewelleryitem',
            name='note',
            field=models.TextField(blank=True, default=''),
        ),
    ]
