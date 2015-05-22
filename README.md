# systemd-make-environment
Let's say that you'd like to run a daemon *food* on your Linux box. The Linux
distribution you are using comes with [http://en.wikipedia.org/wiki/Systemd](systemd) 
as its init system. No one has written a systemd service unit file for *food*,
so you're on your own. *food* needs to have some environment variables set, like
*PIZZA_TYPE*. So far so good.

But, there is a problem: *PIZZA_TYPE* isn't static, such as:
```
PIZZA_TYPE="margerita"
```
... but gets set dynamically by some weird shell magic that kinda looks like this:
```
PIZZA_TYPE=$(grep -Eiv '(meat|eggs)' /var/lib/pizza/pizza-types | head -n1)
```

You can't just stick this expression in */etc/default/food* and say this in the
*/lib/systemd/system/food.service* unit file:
```
EnvironmentFile=/etc/default/food
```
... because *systemd* **doesn't evaulate** the environment files you give it; it
just reads the *EnvironmentFile*, line by line, and sets the environment
variables verbatim. *Some say that this is a security feature. And that you are
better off without it. All we know is...* that the Stig won't set our environment
variables for us. We'll have to do it ourselves.

So, do your environment stuff in */etc/default/food*, and set the *ExecStartPre*
hook in your */lib/systemd/system/food.service* like so:
```
ExecStartPre=/bin/bash /usr/bin/systemd-make-environment.sh --input-file /etc/default/food --output-file /tmp/food-environment
EnvironmentFile=-/tmp/food-environment
```
**NOTE:** The minus (**-**) sign in the *EnvironmentFile* directive is there to
prevent *systemd* thinking that there is something wrong with the setup the
first time it runs the *food* daemon. The first time is a bit special, you know.
The actual environment file doesn't exist (yet), *systemd* checks for its
presence immediately upon issuing *systemctl start food*, and throws up an
error. The minus sign prevents the checking.

If you don't want to leave your environment files hanging around, add:
```
ExecStartPost=/bin/rm /tmp/food-environment
```

And that is pretty much it. Here is a full but slightly more complex example of
a service called *ai* that gets its environment through two environment files,
and gets run with command-line arguments set by the environment variables
*START_DAEMON_ARGS* and *STOP_DAEMON_ARGS*.

*/etc/default/ai-15*:
```
AICODE="15"
. /etc/default/ai-common

# vim: set ts=4 sw=4 et syntax=sh:
```

*/etc/default/ai-common*:
```
AI_HOME="/opt/GuruCue/servers/ai"
JAVA_HOME="/usr/lib/jvm/java-8-oracle"
LOG_DIR="/opt/GuruCue/logs/ai"
PIDFILE="/var/run/jsvc-ai${AICODE}.pid"

CLASSPATH=`JARS=(${AI_HOME}/lib/*); IFS=:; echo "${JARS[*]}"`
RMI_CODEBASE=($AI_HOME/lib/database-*.jar)

START_DAEMON_ARGS=" \
    -nodetach \
    -cp $CLASSPATH \
    -outfile $LOG_DIR/ai${AICODE}.out \
    -errfile $LOG_DIR/ai${AICODE}.err \
    -home $JAVA_HOME \
    -pidfile $PIDFILE \
    -Djava.rmi.server=127.0.0.1 \
    -Djava.rmi.server.codebase=file://$RMI_CODEBASE \
    -Djava.rmi.server.disableHttp=true \
    -Djava.security.policy=/opt/GuruCue/etc/server.policy \
    -XX:MaxPermSize=128m \
    -Xms24576m \
    -Xmx30720m \
    -XX:+UseLargePages \
    -XX:+UseConcMarkSweepGC \
    -XX:+CMSIncrementalMode \
    si.guru.recommendations.RmiServer jdbc:postgresql://127.0.0.1 ${AICODE} \
"

STOP_DAEMON_ARGS=" \
    -cp $CLASSPATH \
    -stop \
    -pidfile $PIDFILE \
    si.guru.recommendations.RmiServer \
"

# vim: set ts=4 sw=4 et syntax=sh:
```

*/lib/systemd/system/ai15.service*:
```
[Unit]
After=network.target rmiregistry.service postgresql.service
Description=GuruCue AI instance #15
Requires=rmiregistry.service postgresql.service

[Service]
EnvironmentFile=-/tmp/ai15-environment
ExecReload=/bin/kill -HUP $MAINPID
ExecStart=/opt/GuruCue/bin/jsvc $START_DAEMON_ARGS
ExecStartPre=/bin/bash /usr/bin/systemd-make-environment.sh --input-file /etc/default/ai15 --output-file /tmp/ai15-environment
ExecStop=/opt/GuruCue/bin/jsvc $STOP_DAEMON_ARGS
PIDFile=/var/run/jsvc-ai15.pid
Restart=on-failure
TimeoutSec=300
Type=simple

[Install]
Alias=ai15.service
```

# vim: set ts=4 sw=0 et tw=80 cc=80:
