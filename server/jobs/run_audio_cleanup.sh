#!/bin/bash
# Audio Cleanup Cron Job
# Runs audio maintenance tasks automatically

# Change to project directory
cd "$(dirname "$0")/.."

# Activate virtual environment if using one
# source venv/bin/activate

# Run cleanup with 30-day grace period
echo "=================================================="
echo "Running audio maintenance at $(date)"
echo "=================================================="

python -m app.jobs.audio_cleanup --grace-days 30

echo ""
echo "Maintenance complete at $(date)"
echo "=================================================="

