import json
import time
import random
from awscrt import io, mqtt
from awsiot import mqtt_connection_builder

#OJO cambiar por el nombre de tu endpoint
ENDPOINT = "a2a5r7xwwc8hs7-ats.iot.us-east-1.amazonaws.com"  # Copiado de Settings

#OJO cambiar por el nombre de su certificado
CERT = "/home/ec2-user/environment/iot-sensor/ancon-certificate.pem.crt"
KEY = "/home/ec2-user/environment/iot-sensor/ancon-private.pem.key"
CA = "/home/ec2-user/environment/iot-sensor/AmazonRootCA1.pem"

CLIENT_ID = "sensor-lab-01"
TOPIC = "ancon/lab01/telemetry"

# Configurar event loop y bootstrap (AWS CRT)
event_loop_group = io.EventLoopGroup(1)
host_resolver = io.DefaultHostResolver(event_loop_group)
client_bootstrap = io.ClientBootstrap(event_loop_group, host_resolver)

# Construir conexión MQTT con mTLS
mqtt_conn = mqtt_connection_builder.mtls_from_path(
    endpoint=ENDPOINT,
    cert_filepath=CERT,
    pri_key_filepath=KEY,
    ca_filepath=CA,
    client_bootstrap=client_bootstrap,
    client_id=CLIENT_ID,
    clean_session=True,
    keep_alive_secs=30
)

print("Conectando al broker MQTT...")
connect_future = mqtt_conn.connect()
connect_future.result()
print("Conectado!")

try:
    while True:
        payload = {
            "deviceId": CLIENT_ID,
            "temperature": round(random.uniform(20, 38), 1),
            "humidity": round(random.uniform(40, 80), 1),
            "ts": int(time.time() * 1000)
        }
        mqtt_conn.publish(
            topic=TOPIC,
            payload=json.dumps(payload),
            qos=mqtt.QoS.AT_LEAST_ONCE
        )
        print("Publicado:", payload)
        time.sleep(3)
finally:
    mqtt_conn.disconnect().result()
    print("Desconectado")
