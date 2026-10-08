IDENTITY
├── project
├── env
└── region

DEPLOYMENT
├── deployment_mode
├── kubapp_account_id
└── database_account_id

DATABASE
├── engine_version
├── instance_class
├── database_name
├── database_port
├── storage_type
├── allocated_storage
└── max_allocated_storage

AVAILABILITY
├── multi_az
├── backup_retention_period
├── deletion_protection
├── backup_window
└── maintenance_window

SECURITY
├── storage_encrypted
└── SOPS-managed credentials

NETWORK
├── same-account → existing KUBAPP network
└── cross-account → database VPC/network configuration

OBSERVABILITY
├── monitoring_interval
└── PostgreSQL/CloudWatch logging configuration
