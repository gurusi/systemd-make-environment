# systemd-make-environment
Let's say that you have written an application *foo* and that you have converted
it into a daemon called *foo****d***. You'd like to run *food* on your Linux box
properly (as a system service with all the bells and whistles), and the Linux
distribution you are running comes with [*systemd*](http://en.wikipedia.org/wiki/Systemd) as its init system. 
Sooner or later, you are bound to need a [*service unit file*](http://www.freedesktop.org/software/systemd/man/systemd.service.html) for *food*
in order to run it the *systemd* way. 

*food* is a bit special. In order to run properly, it needs to have some
environment variables set, like *PIZZA_TYPE*. Okay, but *PIZZA_TYPE* isn't
***static***, such as:
```
PIZZA_TYPE="margerita"
```
... but instead gets set ***dynamically*** by some clever shell magic you
devised in order to save you tedious programming in -- I dunno -- Java. The
magic kinda looks like this:
```
PIZZA_TYPE=$(grep -Eiv '(meat|eggs)' /var/lib/pizza/pizza-types | head -n1)
```

You can't just stick this expression in */etc/default/food* and instruct
*systemd* to use it in tje */lib/systemd/system/food.service* unit file:
```
EnvironmentFile=/etc/default/food
```
... because *systemd* **doesn't evaulate** the environment files you give it; it
just reads the *EnvironmentFile*, line by line, and sets the environment
variables verbatim. *Some say that this is a security feature. And that you are
better off without it. All we know is...* that the Stig won't set our
environment variables for us. We'll have to do it ourselves.

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
