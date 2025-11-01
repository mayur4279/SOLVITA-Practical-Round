if systemctl is-active --quiet mysql; then
    echo "MySQL is running"
    
    # Create backup directory
    mkdir -p /tmp/mysql_backups
    
    # Backup all databases
    backup_file="/tmp/mysql_backups/backup_$(date +%Y%m%d_%H%M%S).sql"
    
    echo "Creating backup..."
    mysqldump -u root --all-databases > $backup_file 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "Backup created: $backup_file"
    else
        echo "Backup failed! Check MySQL credentials"
    fi
else
    echo "MySQL is not running - skipping backup"
fi