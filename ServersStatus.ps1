# Script ServersStatus.ps1
# Autor: Fernando Cisneros Chavez (verdevenus23@gmail.com)
# Fecha: 26 de septiembre de 2025
$servidores = Get-Content "C:\...\servidores.txt" | ForEach-Object {
    $partes = $_ -split "`t`t"
    if ($partes.Count -eq 4) {
        [PSCustomObject]@{
            Direccion = $partes[0].Trim()
            Nombre    = $partes[1].Trim()
            Usuario   = $partes[2].Trim()
            Password  = $partes[3].Trim()
        }
    }
}

# Función para obtener uptime
function Obtener-Uptime {
    param (
        [string]$IP,
        [string]$Usuario,
        [string]$Password,
        [int]$TimeoutSec = 100  # Tiempo maximo por servidor (en segundos)
    )

    try {
        # Crear credenciales seguras
        $secpass = ConvertTo-SecureString $Password -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential ($Usuario, $secpass)

        # Crear un trabajo en segundo plano
        $job = Start-Job -ScriptBlock {
            param ($ip, $cred)

            Invoke-Command -ComputerName $ip -Credential $cred -ScriptBlock {
                net stats workstation
            } -Authentication Negotiate -ErrorAction Stop

        } -ArgumentList $IP, $cred

        # Esperar al trabajo con timeout
        $finished = Wait-Job -Job $job -Timeout $TimeoutSec

        if ($finished) {
            # Obtener salida del trabajo
            $output = Receive-Job -Job $job
            Remove-Job -Job $job

            foreach ($line in $output) {
                if ($line -like "*desde*") {
                    $fechaStr = ($line -replace '.*desde', '' -replace '\s+', ' ').Trim()
                    $formatos = @(
                        "dd/MM/yyyy H:mm:ss",
                        "dd/MM/yyyy HH:mm:ss",
                        "dd/MM/yyyy h:mm:ss tt",
                        "dd/MM/yyyy hh:mm:ss tt",
                        "MM/dd/yyyy H:mm:ss",
                        "MM/dd/yyyy HH:mm:ss",
                        "MM/dd/yyyy h:mm:ss tt",
                        "MM/dd/yyyy hh:mm:ss tt"
                    )

                    foreach ($formato in $formatos) {
                        try {
                            $fecha = [datetime]::ParseExact($fechaStr, $formato, $null)
                            break
                        } catch { $fecha = $null }
                    }

                    if ($fecha) {
                        $dias = (New-TimeSpan -Start $fecha -End (Get-Date)).Days
                        return $dias
                    } else {
                        return "Fecha invalida: $fechaStr"
                    }
                }
            }

            return "No se encontro linea de fecha"
        } else {
            # Timeout
            Stop-Job -Job $job
            Remove-Job -Job $job
            return "Timeout (${TimeoutSec}s)"
        }

    } catch {
        return "Error: $($_.Exception.Message)"
    }
}

# Lista para guardar resultados
$resultados = @()

# Procesar cada servidor
foreach ($srv in $servidores) {
    $direccion = $srv.Direccion
    $nombre    = $srv.Nombre
    $usuario   = $srv.Usuario
    $password  = $srv.Password

    Write-Host "Verificando $nombre [$direccion]..."

    $ping = Test-Connection -ComputerName $direccion -Count 1 -Quiet

    if ($ping) {
        $uptime = Obtener-Uptime -IP $direccion -Usuario $usuario -Password $password -TimeoutSec 71
        $estado = "Activo"
    } else {
        $uptime = "Inaccesible"
        $estado = "Inaccesible"
    }

    $resultados += [PSCustomObject]@{
        "Nombre Servidor" = $nombre
        "Direccion"       = $direccion
        "Estado"          = $estado
        "Dias Encendido"  = $uptime
    }
}

# Guardar resultados en CSV
$resultados | Export-Csv -Path "C:\...\monitoreo_servidores.csv" -NoTypeInformation -Encoding UTF8
Write-Host "`n Monitoreo completo. Resultados guardados en 'monitoreo_servidores.csv'"

# Parámetros de conexión y archivo
$server = "server"
$database = "database"
$tablaStaging = "schema.stg_statusServers_tbl"
$csvPath = "C:\...\monitoreo_servidores.csv"
$fechaCarga = Get-Date

# Leer CSV
$data = Import-Csv -Path $csvPath

# Filtrar filas con "Dias Encendido" numérico
$dataFiltrada = $data | Where-Object {
    $_.'Dias Encendido' -match '^\d+$'
}

# Agregar columna FechaCarga
$dataFiltrada | ForEach-Object {
    $_ | Add-Member -NotePropertyName 'FechaCarga' -NotePropertyValue $fechaCarga
}

# Crear conexión SQL
$connectionString = "Server=$server;Database=$database;Integrated Security=True"
$connection = New-Object System.Data.SqlClient.SqlConnection $connectionString
$connection.Open()

# Limpiar tabla staging
$cmd = $connection.CreateCommand()
$cmd.CommandText = "TRUNCATE TABLE $tablaStaging"
$cmd.ExecuteNonQuery()

# Preparar BulkCopy
$bulkCopy = New-Object Data.SqlClient.SqlBulkCopy $connection
$bulkCopy.DestinationTableName = $tablaStaging

# Crear DataTable con columnas en orden
$dataTable = New-Object System.Data.DataTable

@("NombreServidor", "Direccion", "Estado", "DiasEncendido", "FechaCarga") | ForEach-Object {
    [void]$dataTable.Columns.Add($_)
}

# Llenar DataTable
foreach ($row in $dataFiltrada) {
    $dataRow = $dataTable.NewRow()
    $dataRow["NombreServidor"] = $row.'Nombre Servidor'
    $dataRow["Direccion"] = $row.Direccion
    $dataRow["Estado"] = $row.Estado
    $dataRow["DiasEncendido"] = $row.'Dias Encendido'
    $dataRow["FechaCarga"] = $row.FechaCarga
    $dataTable.Rows.Add($dataRow)
}

# Cargar datos a SQL
$bulkCopy.WriteToServer($dataTable)

$mergeCmd = $connection.CreateCommand()
$mergeCmd.CommandText = @"
MERGE schema.statusServers_tbl AS target
USING schema.stg_statusServers_tbl AS source
ON target.[NombreServidor] = source.[NombreServidor]
WHEN MATCHED THEN
    UPDATE SET 
        target.Direccion = source.Direccion,
        target.Estado = source.Estado,
        target.[DiasEncendido] = source.[DiasEncendido],
        target.FechaCarga = source.FechaCarga
WHEN NOT MATCHED THEN
    INSERT ([NombreServidor], Direccion, Estado, [DiasEncendido], FechaCarga)
    VALUES (source.[NombreServidor], source.Direccion, source.Estado, source.[DiasEncendido], source.FechaCarga);
"@
$mergeCmd.ExecuteNonQuery()

# Cerrar conexión
$connection.Close()
