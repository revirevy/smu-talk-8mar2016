#!/bin/bash

sudo pip install numpy pandas  

if grep -q isMaster /mnt/var/lib/info/instance.json; then
  sudo pip install jupyter ipython matplotlib
  sudo yum install -y git

  # Password is sfvhxj7d
  # >>> from notebook.auth import passwd
  # >>> passwd()
  # Enter password: 
  # Verify password: 
  # 'sha1:fe04bf1e1deb:4af414c52f1559e3006d73e6ab56479afa332751'
  
  cd ~hadoop

  openssl req \
    -new \
    -newkey rsa:2048 \
    -days 365 \
    -nodes \
    -x509 \
    -subj "/C=AU/ST=Some-State/O=Internet Widgits Pty Ltd" \
    -keyout mykey.key \
    -out mycert.pem


  # /usr/loca/bin does not exists during emr bootstrap
  PATH=$PATH:/usr/local/bin/

  jupyter notebook --generate-config
  echo "c.NotebookApp.password = u'sha1:fe04bf1e1deb:4af414c52f1559e3006d73e6ab56479afa332751'" >> ~/.jupyter/jupyter_notebook_config.py
  
  git clone https://github.com/tsailiming/smu-talk-8mar2016 

  mkdir -p /home/hadoop/.local/share/jupyter/kernels/pyspark

  cat << EOF > /home/hadoop/.local/share/jupyter/kernels/pyspark/kernel.json
{
 "display_name": "Spark 1.6.0 (Python)",
 "language": "python",
 "argv": [
  "python",
  "-m",
  "IPython.kernel",
  "-f",
  "{connection_file}"
 ]
}
EOF

  source /etc/spark/conf/spark-env.sh
  export PYTHONPATH=$SPARK_HOME/python:$SPARK_HOME/python/lib/py4j-0.9-src.zip

  nohup jupyter notebook --ip=0.0.0.0 \
    --certfile=~/mycert.pem --keyfile ~/mykey.key --no-browser \
    --notebook-dir=~/smu-talk-8mar2016 &
fi