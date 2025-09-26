# Script ServerStatus.py
# Autor: Fernando Cisneros Chavez (verdevenus23@gmail.com)
# Fecha: 25 de septiembre de 2025
import winrm
import pandas as pd
import subprocess
from datetime import datetime

# Leer lista con direccion, nombre, usuario y contraseña
archivo_servidores = "servidores.txt"
servidores = []
with open(archivo_servidores, encoding="utf-8") as f:
    for linea in f:
        partes = linea.strip().split('\t\t')
        if len(partes) == 4:
            direccion, nombre, usuario, password = partes
            servidores.append({"direccion": direccion.strip(), "nombre": nombre.strip(), "usuario": usuario.strip(), "password": password.strip()})


def esta_activo(host):
    try:
        resultado = subprocess.run(["ping", "-n", "1", host], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return "TTL=" in resultado.stdout
    except:
        return False

def obtener_uptime(host):
    try:
        session = winrm.Session(host, auth=(usuario, password), transport='ntlm')
        response = session.run_cmd('net stats workstation')

        if response.status_code != 0:
            return "Error al ejecutar comando"

        salida = response.std_out.decode('utf-8', errors='ignore')
        for linea in salida.splitlines():
            if "Estadsticas desde" in linea:
                fecha_str = linea.split("desde")[-1].strip()
                fecha_str = fecha_str.lower().replace("p. m.", "PM").replace("a. m.", "AM")
                try:
                    fecha_inicio = datetime.strptime(fecha_str, '%d/%m/%Y %H:%M:%S %p')  # Formato ES
                except:
                    fecha_inicio = datetime.strptime(fecha_str, '%d/%m/%Y %H:%M:%S')

                dias = (datetime.now() - fecha_inicio).days
                return dias
        return f"No se encontro fecha de inicio {salida}"

    except Exception as e:
        return f"Error: {str(e)}"

# Procesar cada servidor
resultados = []
for srv in servidores:
    direccion = srv["direccion"]
    nombre = srv["nombre"]
    usuario = srv["usuario"]
    password = srv["password"]

    if esta_activo(direccion):
        uptime = obtener_uptime(direccion)
        estado = "Activo"
    else:
        uptime = "Inaccesible"
        estado = "Inaccesible"

    resultados.append({
        "Nombre Servidor": nombre,
        "Direccion": direccion,
        "Estado": estado,
        "Dias Encendido": uptime
    })

# Guardar resultados
df = pd.DataFrame(resultados)
#df["Dias Encendido"] = pd.to_numeric(df["Dias Encendido"], errors='coerce')
#df = df.sort_values(by="Dias Encendido", ascending=False)
df.to_csv("monitoreo_servidores.csv", index=False)
print("✅ Monitoreo completo. Resultados guardados en 'monitoreo_servidores.csv'")

#winrm quickconfig
#Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true
#Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true
