#!/usr/bin/perl
use DateTime::Format::ISO8601;

$PATH = "/srv/mailtrack/scripts";
require("$PATH/etc/config.pl");

my $dbh = DBI->connect($connectionInfo,$userid,$passwd, {mysql_enable_utf8=>1})
        or die "Can't connect to the database.\n";

my $insert_accesos = $dbh->prepare("
        INSERT INTO accesos (usuario, ip, tipo, protocolo, fecha, estado)
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE fecha = ?;
");
my $update_accesos = $dbh->prepare("
        UPDATE accesos
        SET contador = contador + ?
        WHERE usuario = ?
        AND tipo = ?
        AND protocolo = ?
        AND estado = ?;
");

open(IN,"$PATH/log/temp") or die("No puedo abrir el fichero temp!\n");

while (<IN>) {
        if ($_ =~ /(\S+) \S+ dovecot: (pop3|imap)-login: Login: user=<(.*?)>, .*, rip=(.*?),/) {
                my ($fecha, $protocolo, $usuario, $ip) = ($1, $2, $3, $4);
                my $tipo = "Correo USAL";
                my $timestamp = DateTime::Format::ISO8601->parse_datetime($fecha)->epoch();
                my $estado = 0; # Aceso correcto
                my $num_accesos = 1;

                $insert_accesos->execute($usuario, $ip, $tipo, $protocolo, $timestamp, $estado, $timestamp);
                $update_accesos->execute($num_accesos, $usuario, $tipo, $protocolo, $estado);
        } elsif ($_ =~ /(\S+) \S+ dovecot: (pop3|imap)-login: Disconnected \(auth failed, (\d+) attempts in \d+ secs\): user=<(.+?)>, .*, rip=(.+?), /) {
                my ($fecha, $protocolo, $num_accesos, $usuario, $ip) = ($1, $2, $3, $4, $5);
                my $tipo = "Correo USAL";
                my $timestamp = DateTime::Format::ISO8601->parse_datetime($fecha)->epoch();
                my $estado = 1; # Aceso inválido

                $insert_accesos->execute($usuario, $ip, $tipo, $protocolo, $timestamp, $estado, $timestamp);
                $update_accesos->execute($num_accesos, $usuario, $tipo, $protocolo, $estado);
        }
}
