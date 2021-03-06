#!/bin/sh
set -eo pipefail

WORKERS=${WORKERS:-1}
WORKER_CLASS=${WORKER_CLASS:-gevent}
ACCESS_LOG=${ACCESS_LOG:--}
ERROR_LOG=${ERROR_LOG:--}
WORKER_TEMP_DIR=${WORKER_TEMP_DIR:-/dev/shm}
SECRET_KEY_FILE=${SECRET_KEY_FILE:-.ctfd_secret_key}

# Check that a .ctfd_secret_key file or SECRET_KEY envvar is set
if [ ! -f "$SECRET_KEY_FILE" ] && [ -z "$SECRET_KEY" ]; then
    if [ $WORKERS -gt 1 ]; then
        echo "[ ERROR ] You are configured to use more than 1 worker."
        echo "[ ERROR ] To do this, you must define the SECRET_KEY environment variable or create $SECRET_KEY_FILE."
        echo "[ ERROR ] Exiting..."
        exit 1
    fi
fi

# Check that the database is available
if [ -n "$DATABASE_URL" ]
    then
    url=`echo $DATABASE_URL | awk -F[@//] '{print $4}'`
    database=`echo $url | awk -F[:] '{print $1}'`
    port=`echo $url | awk -F[:] '{print $2}'`
    echo "Waiting for $database:$port to be ready"
    while ! mysqladmin ping -h "$database" -P "$port" --silent; do
        # Show some progress
        echo -n '.';
        sleep 1;
    done
    echo "$database is ready"
    # Give it another second.
    sleep 1;
fi

# Initialize database
python manage.py db upgrade

# Fix volume permissions
chown -R ctfd:ctfd /var/log/CTFd /var/lib/CTFd/uploads

# Start CTFd
if [ ! -z "$DEBUG" ]; then
    echo "Starting CTFd in debug mode"
    exec su-exec ctfd:ctfd python serve.py --port 8000
else
    echo "Starting CTFd"
    exec su-exec ctfd:ctfd gunicorn 'CTFd:create_app()' \
        --bind '0.0.0.0:8000' \
        --workers $WORKERS \
        --worker-tmp-dir "$WORKER_TEMP_DIR" \
        --worker-class "$WORKER_CLASS" \
        --access-logfile "$ACCESS_LOG" \
        --error-logfile "$ERROR_LOG"
fi
