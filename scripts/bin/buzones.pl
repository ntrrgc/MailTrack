#!/usr/bin/perl
#
# Procesamiento de maillog de buzones (Postfix + Dovecot) para Seguimiento de correo
# -------------------------------------------------------------------------------------
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

use feature "state";
use Encode;
use HTML::Entities qw(encode_entities);
use DateTime::Format::ISO8601;

our $PATH = "/srv/mailtrack/scripts";
require("$PATH/etc/config.pl");
require("$PATH/bin/funciones.pl");

# Connect to the database
our $dbh = DBI->connect($connectionInfo,$userid,$passwd, {mysql_enable_utf8=>1}) 
        or die "Can't connect to the database.\n";

# label_info stores some information associated to Postfix labels:
#  - mid
#  - from
#  - subject
#  - expires_in (timestamp)
# The objects are removed once processing for that label has ended or at the
# end of the script if they are old enough (1 hour).
our %label_info = ();
$dbh->do("CREATE TABLE IF NOT EXISTS
label_info_store (
        `label` CHAR(16) PRIMARY KEY,
        `mid` VARCHAR(255),
        `from` VARCHAR(255),
        `subject` VARCHAR(255),
        `expires_in` INTEGER);");

# mid_info stores some information associated with message-id's:
#  - subject
#  - expires_in (timestamp)
# The objects are removed only when they reach the expiration time (24 hours).
# This object allows us to retrieve the subject for lists' messages, which
# appears only once, when the mail is received in the lists machine, but not
# in deliveries.
$dbh->do("CREATE TABLE IF NOT EXISTS
mid_info_store (
        `mid` VARCHAR(255) PRIMARY KEY,
        `subject` VARCHAR(255),
        `expires_in` INTEGER);");

our %sth_store_get = ();
our %sth_store_set = ();
our %fields_by_index = (
        'label' => ['mid', 'from', 'subject'],
        'mid' => ['subject'],
);
while ((my $index, my $fields) = each(%fields_by_index)) {
        my $table = $index . "_info_store";
        foreach my $field (@$fields) {
                $sth_store_get{$index}->{$field} = $dbh->prepare("
                        SELECT (`$field`)
                        FROM $table
                        WHERE `$index` = ?");
                $sth_store_set{$index}->{$field} = $dbh->prepare("
                        INSERT INTO $table
                        (`$index`, `$field`, expires_in)
                        VALUES (?, ?, ?)
                        ON DUPLICATE KEY
                        UPDATE `$field` = ?, `expires_in` = ?;");
        }
}

sub get_label_info {
        my ($label, $field) = @_;

        my $sth = $sth_store_get{"label"}->{$field} or die "Unknown field: $field";
        $sth->execute($label);

        my $value;
        if ($sth->rows) {
                my @row = $sth->fetchrow_array();
                $value = $row[0];
        }
        
        $sth->finish();
        return $value;
}
sub set_label_info {
        my ($label, $field, $value) = @_;
        my $expires_in = DateTime->now()->epoch() + 3600;

        my $sth = $sth_store_set{"label"}->{$field} or die "Unknown field: $field";
        $sth->execute($label, $value, $expires_in, $value, $expires_in);
}
sub remove_label_info {
        my ($label,) = @_;

        state $sth = $dbh->prepare("
                DELETE FROM label_info_store
                WHERE `label` = ?;");

        $sth->execute($label);
}

sub get_mid_info {
        my ($mid, $field) = @_;

        my $sth = $sth_store_get{"mid"}->{$field} or die "Unknown field: $field";
        $sth->execute($mid);

        my $value;
        if ($sth->rows) {
                my @row = $sth->fetchrow_array();
                $value = $row[0];
        }
        
        $sth->finish();
        return $value;
}
sub set_mid_info {
        my ($mid, $field, $value) = @_;
        my $expires_in = DateTime->now()->epoch() + 24 * 3600;

        my $sth = $sth_store_set{"mid"}->{$field} or die "Unknown field: $field";
        $sth->execute($mid, $value, $expires_in, $value, $expires_in);
}

sub clean_storage {
        my $now = DateTime->now()->epoch();

        $dbh->prepare("DELETE FROM label_info_store
                       WHERE `expires_in` < ?")->execute($now);

        $dbh->prepare("DELETE FROM mid_info_store
                      WHERE `expires_in` < ?")->execute($now);
}

open(IN,"$PATH/log/temp") or die("No puedo abrir el fichero temp!\n");

while (<IN>) {
	if($_=~/(.+) postfix\/cleanup\[(.+)\]: (.+): message-id=(.+)/){
		my $label = $3;
		my $mid = $4;

                set_label_info($label, "mid", $mid);

                # If we knew the subject for this message, associate it with its
                # message-id.
                if (my $subject = get_label_info($label, "subject")) {
                        set_mid_info($mid, "subject", $subject);
                }
	}
	elsif($_=~/(.+) postfix\/cleanup\[(.+)\]: (.+): info: header subject/i){
                my $label = $3;

                # Some messages have several Subject lines (e.g. mail returned to sender)
                # We choose the first subject.
                if (!get_label_info($label, "subject")) {
                        my $subject = obtener_asunto($_);
                        set_label_info($label, "subject", $subject);

                        # We mantain a hash mid -> subject in order to be able to recover
                        # message subjects in list deliveries.
                        #
                        # Postfix logs the subject when the mail arrives to the mailing
                        # lists machine, but not when it is delivered to its recipients.
                        if (my $mid = get_label_info($label, "mid")) {
                                set_mid_info($mid, "subject", $subject);
                        }
                }
	}
	elsif($_=~/(.+) postfix\/qmgr\[(.+)\]: (.+): from=<(.+)>/){
                my $label = "$3";
                set_label_info($label, "from", $4);
	} 
	elsif($_=~/(.+) (.+) postfix.+\[.+\]: (.+): to=<(.+?)>(.+) status=(.+) \((.+)\)/){
		my $date = DateTime::Format::ISO8601->parse_datetime($1)->epoch();
		my $machine = $2;
		my $label = $3;
		my $mid = get_label_info($label, "mid");
                if (!$mid) {
                        state $already_reported_labels = {};
                        if (!defined $already_reported_labels->{$label}) {
                                print("Warning: No message-id recorded for label $label. Skipping...\n");
                                $already_reported_labels->{$label} = 1;
                        }
                        next;
                }
		my $from = limpia_lavadora(get_label_info($label, "from"));
                if (!$from) {
                        # Placeholder name if from is absent
			$from = "Sistema de correo";
                }
		my $to = $4;
		my $redir_text = $5;
		my $alias_email = "";
		my $status_text = $6;
		my $description = "- Postfix informó del siguiente estado: $status_text";
		
		my $aditional_info = "";

		my $status_code = $ENTREGADO_LOCAL;
		# Check if a mail alias is in use
		if($redir_text =~ / orig_to=<(.+?)>/){
			$alias_email = $to;
			$to = $1;
			$status_code = $ENTREGADO_REDIRECCION;
			$aditional_info = "- Postfix/smtp informó: El destinatario utiliza una redirección desde la cuenta <i>".
                                          encode_entities($to)."</i> a la cuenta <i>".encode_entities($alias_email)."</i>.";
			
			 #Incrementamos el número de correos redirigidos
                        $query = "UPDATE estadisticas SET redirecciones = redirecciones + 1;";
                        $sth = $dbh->prepare($query);
                        $sth->execute();
		}
                if($status_text ne 'sent')
                {
                        $status_code = $ERROR_BUZONES;
                }

                my $subject = get_label_info($label, "subject") || get_mid_info($mid, "subject") || "";
                if ($subject =~ /^\[SPAM\]/ && $status_code != $ERROR_BUZONES) {
                        $status_code = $SPAM_ENTREGADO_LOCAL;
                }

                my $subject_db;
                if ($subject =~ /\S/) {
                        $subject_db = encode_entities($subject);
                } else {
                        $subject_db = "<i>(sin asunto)</i>";
                }

                $query = "INSERT INTO mensajes (message_id,mfrom,mto,redirect,asunto,estado,fecha) ".
                         "VALUES (?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE estado = ?;";

                $sth = $dbh->prepare($query);
                $sth->execute($mid, $from, $to, $alias_email, $subject_db, $status_code, $date, $status_code);

                #Incrementamos el número de correos procesados
                $query = "UPDATE estadisticas SET procesados = procesados + 1;";
                $sth = $dbh->prepare($query);
                $sth->execute();

		#En cualquier caso, actualizamos el historial del mensaje
		$query = "INSERT IGNORE INTO historial (message_id,estado,hto,fecha,maquina,descripcion,adicional) ".
                         "VALUES (?,?,?,?,?,?,?);";
		$sth = $dbh->prepare($query);
		$sth->execute($mid, $status_code, $to, $date, $machine, $description, $aditional_info);

		#Incrementamos el numero de correos para dominios propios si el estado fue entregado local
		if ($status_code == $ENTREGADO_LOCAL)
		{
			#Incrementamos el número de correos redirigidos a alias o dom. virtuales
                        my $query = "UPDATE estadisticas SET interno = interno + 1;";
                        $sth = $dbh->prepare($query);
                        $sth->execute();
		}

	}
        elsif($_=~/(.+) postfix\/qmgr\[(.+)\]: (.+): removed/){
                my $label = $3;

                # Once the message is processed we can remove it from the storage
                # (Note we keep the mid -> subject association for a longer time)
                remove_label_info($label);
        }
}

clean_storage();
$dbh->disconnect();
close(IN);
