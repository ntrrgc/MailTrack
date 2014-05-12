#!/usr/bin/perl

$PATH = "/srv/mailtrack/scripts";
require("$PATH/etc/config.pl");

# Realizamos la conexión a la base de datos
my $dbh = DBI->connect($connectionInfo,$userid,$passwd, {mysql_enable_utf8=>1})
        or die "Can't connect to the database.\n";

$dbh->do("
        DELETE FROM mensajes
        WHERE fecha < UNIX_TIMESTAMP(DATE_SUB(UTC_TIMESTAMP(), INTERVAL 1 MONTH));
");

$adas_dbh->disconnect;
