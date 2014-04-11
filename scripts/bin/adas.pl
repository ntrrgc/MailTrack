#!/usr/bin/perl
#
# Procesamiento de maillog de rclogin  para Seguimiento de correo
# ------------------------------------------------------------------
#/*
# *    Copyright 2011 Víctor Téllez Lozano <vtellez@us.es>
# *
# *    This file is part of Seguimiento.
# *
# *    Seguimiento is free software: you can redistribute it and/or modify it
# *    under the terms of the GNU Affero General Public License as
# *    published by the Free Software Foundation, either version 3 of the
# *    License, or (at your option) any later version.
# *
# *    Seguimiento is distributed in the hope that it will be useful, but
# *    WITHOUT ANY WARRANTY; without even the implied warranty of
# *    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# *    Affero General Public License for more details.
# *
# *    You should have received a copy of the GNU Affero General Public
# *    License along with Seguimiento.  If not, see
# *    <http://www.gnu.org/licenses/>.
# */

$PATH = "/srv/mailtrack/scripts";
require("$PATH/etc/config.pl");

# Realizamos la conexión a la base de datos
my $adas_dbh = DBI->connect($adas_connectionInfo, $adas_userid, $adas_passwd, {mysql_enable_utf8=>1})
        or die "No se pudo conectar a la base de datos de adAS.\n";
my $mailtrack_dbh = DBI->connect($connectionInfo,$userid,$passwd, {mysql_enable_utf8=>1})
        or die "Can't connect to the database.\n";

# Sólo se procesarán intentos de autenticación con id superiores a este.
my $min_id_auth = 9904566;
$PATH = "/srv/mailtrack/scripts";

# Obtiene el último id de autenticación del que mailtrack tiene información
if (open(FILE, "$PATH/log/last_id_auth")) {
        $last_id_auth = int(join("", <FILE>));
} else {
        # El archivo no existe
        $last_id_auth = $min_id_auth;
}
close FILE;
print("Last ".$last_id_auth."\n");

my $adas_sth = $adas_dbh->prepare("
SELECT auth.id_auth AS id_auth,
       auth.id_user AS id_user,
       auth.timestamp AS timestamp,
       auth.success AS success,
       accesses.resource AS resource,
       (SELECT value
        FROM extra_info
        WHERE extra_info.session_hash = auth.session_hash
        AND extra_info.key = 'ip_client'
        LIMIT 1) AS ip_client
FROM authentications auth
JOIN accesses ON auth.session_hash = accesses.session_hash
WHERE id_auth > ?
ORDER BY id_auth ASC;
");

$adas_sth->execute($last_id_auth);

my $insert_accesos = $mailtrack_dbh->prepare("
        INSERT INTO accesos (usuario, ip, tipo, protocolo, fecha, estado)
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE fecha = ?;
");
my $update_accesos = $mailtrack_dbh->prepare("
        UPDATE accesos
        SET contador = contador + 1
        WHERE usuario = ?
        AND tipo = ?
        AND protocolo = ?
        AND estado = ?;
");

while (@acceso = $adas_sth->fetchrow_array) {
        my ($id_auth, $id_user, $timestamp, $success, $resource, $ip_client) = @acceso;

        my $tipo = "buzonweb";
        my $protocolo = "idusal";
        my $estado = $success == 1 ? 0 : 1;
        my $tipo;
        if ($resource =~ /^https?:\/\/([^\/]+)/) {
                $tipo = $1;
        } else {
                $tipo = "desconocido";
        }
        $insert_accesos->execute($id_user, $ip_client, $tipo, $protocolo, $timestamp, $estado, $timestamp);

        $update_accesos->execute($id_user, $tipo, $protocolo, $estado);

        $last_id_auth = $id_auth;
}

$adas_dbh->disconnect;
$mailtrack_dbh->disconnect;

open(FILE, ">", "$PATH/log/last_id_auth");
print FILE $last_id_auth;
close FILE;
