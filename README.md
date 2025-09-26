# Servers-Status
Monitorea los días de ejecución de una lista de servidores y actualiza una tabla en sql server con la información obtenida.

La version powershell genera la información y actualiza la tabla. Primero crea jobs donde se procesan comandos de WinRM para cada consulta y les da un tiempo limite, esto para controlar servidores que responden muy lento y no quedar sin información, luego procesa las respuestas para saber cuantos dias tienen en ejecucion, genera un resumen de nombres de servidores,  si pudieron ser accesibles mediante ping, direcciones dias en ejecución y el momento en el que se consulto la información. 

Para el caso de la version en python unicamente hace uso de WinRM para recolectar la información y guardarla en un archivo CSV.
