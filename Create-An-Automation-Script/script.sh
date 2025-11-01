#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RESET='\033[0m'
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

separator="================================================================================"

print_header() {
    echo -e "\n${CYAN}${BOLD}$1${RESET}"
    echo "$separator"
}


# CPU Usages


top_output=$(top -bn1)

cpu_idle=$(echo "$top_output" | grep "Cpu(s)" | sed 's/.*, *\([0-9.]*\)%* id.*/\1/')
cpu_usage=$(awk -v idle="$cpu_idle" 'BEGIN { printf("%.1f", 100 - idle) }')

print_header "CPU Usage"
echo -e "Usage         : ${GREEN}${cpu_usage}%${RESET}"



# Memory Usage  

read total_memory available_memory <<< $(awk '/MemTotal/ {t=$2} /MemAvailable/ {a=$2} END {print t, a}' /proc/meminfo)
used_memory=$((total_memory - available_memory))

used_memory_percent=$(awk -v u=$used_memory -v t=$total_memory 'BEGIN { printf("%.1f", (u / t) * 100) }')
free_memory_percent=$(awk -v a=$available_memory -v t=$total_memory 'BEGIN { printf("%.1f", (a / t) * 100) }')

# Convert from kB to MB 
total_memory_mb=$(awk -v t=$total_memory 'BEGIN { printf("%.1f", t/1024) }')
used_memory_mb=$(awk -v u=$used_memory 'BEGIN { printf("%.1f", u/1024) }')
available_memory_mb=$(awk -v a=$available_memory 'BEGIN { printf("%.1f", a/1024) }')

print_header "Memory Usage"
printf "Total Memory    : ${YELLOW}%-10s MB${RESET}\n" "$total_memory_mb"
printf "Used Memory     : ${YELLOW}%-10s MB${RESET} (%s%%)\n" "$used_memory_mb" "$used_memory_percent"
printf "Free/Available  : ${YELLOW}%-10s MB${RESET} (%s%%)\n" "$available_memory_mb" "$free_memory_percent"


# Top 3 CPU Processes 

print_header "Top 5 Processes by CPU"
ps aux --sort=-%cpu | awk 'NR==1 || NR<=4 { printf "%-10s %-6s %-5s %-5s %s\n", $1, $2, $3, $4, $11 }'



# MySQL backup Script

echo ""
echo "Creating MySQL backup..."
mysqldump -u root --all-databases > /tmp/backup_$(date +%Y%m%d).sql 2>/dev/null


if systemctl is-active --quiet mysql; then
    echo "MySQL is running"
    
    sudo mkdir -p /tmp/mysql_backups
    
    backup_file="/tmp/mysql_backups/backup_$(date +%Y%m%d_%H%M%S).sql"
    
    echo "Creating backup..."
    sudo mysqldump -u root --all-databases > $backup_file 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "Backup created: $backup_file"
    else
        echo "Backup failed! Check MySQL credentials"
    fi
else
    echo "MySQL is not running - skipping backup"
fi


