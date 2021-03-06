#!/bin/bash
#
# Script de alimentación de la base de datos de seguimiento
# -----------------------------------------------------------------------
#/*
# *    Copyright 2010 Víctor Téllez Lozano <vtellez@us.es>
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

RUTA="/srv/mailtrack/scripts"
RUTA_LOG="/var/local/lib/mailtrack/logs"
LOCK_FILE="/run/mailtrack/seguimiento_flag_lock"

( flock -n 9 || exit

        date
        echo ""
        echo "------------------------------------------------------------------"
        echo "   >>>>> Iniciando descarga de ficheros de logs remotos"
        echo "------------------------------------------------------------------"
        echo ""

        if [ ! -d "$RUTA_LOG" ]; then
                mkdir $RUTA_LOG
        fi

        #Recorrido inverso para la descarga de los logs
        grep -v '#' $RUTA/etc/$1 | tac | while read line 
        do
                HOST=`echo $line |  cut -d , -f1`
                IP=`echo $line |  cut -d , -f2`
                LOG=`echo $line |  cut -d , -f3`
                PROGRAMA=`echo $line |  cut -d , -f4`

                if [ "$PROGRAMA" = "adas.pl" ]; then
                        # El script de adAS no necesita descarga de logs
                        continue
                fi

                echo "Descargando el log $LOG de $HOST......."
                scp $IP:$LOG $RUTA_LOG/$HOST.actual
                echo "Descarga completada (OK)."
                echo ""

                if [ "$PROGRAMA" = "salida.pl" ]; then
                        perl $RUTA/bin/mtrack $RUTA_LOG/$HOST.actual > $RUTA_LOG/temp
                        mv $RUTA_LOG/temp $RUTA_LOG/$HOST.actual
                fi
                if [ "$PROGRAMA" = "antivirus.pl" ]; then
                        #Comprobamos que la ultima lina no sea el resultado de spam
                        CONT=`tail -1 $RUTA_LOG/$HOST.actual | grep "spamd: result" | wc -l`;
                        if [ $CONT -eq 1 ]; then
                                cp $RUTA_LOG/$HOST.actual $RUTA_LOG/copia
                                sed '$d' $RUTA_LOG/copia > $RUTA_LOG/$HOST.actual
                                rm $RUTA_LOG/copia
                        fi
                fi
                if [ "$PROGRAMA" = "listas.pl" ]; then
                        #Comprobamos que la ultima lina no sea la de from
                        CONT=`tail -1 $RUTA_LOG/$HOST.actual | grep "from=<" | wc -l`;
                        if [ $CONT -eq 1 ]; then
                                cp $RUTA_LOG/$HOST.actual $RUTA_LOG/copia
                                sed '$d' $RUTA_LOG/copia > $RUTA_LOG/$HOST.actual
                                rm $RUTA_LOG/copia
                        fi
                fi
        done

        echo ""
        echo "------------------------------------------------------------------"
        echo "   >>>>> Descarga de logs completada, inicio de procesamiento"
        echo "------------------------------------------------------------------"
        echo ""
        # Recorrido en orden natural para la ejecución de procesamiento de los logs
        grep -v '#' $RUTA/etc/$1 | while read line 
        do 
                HOST=`echo $line |  cut -d , -f1`
                PROGRAMA=`echo $line |  cut -d , -f4`

                if [ ! -f $RUTA_LOG/$HOST ]
                then
                    echo "" > $RUTA_LOG/$HOST;
                fi

                if  [ "$PROGRAMA" != "adas.pl" ]; then
                        diff $RUTA_LOG/$HOST.actual $RUTA_LOG/$HOST | grep "^<" | sed -e 's/^< //g' > $RUTA/log/temp
                fi

                echo ""
                echo "Ejecutando $PROGRAMA sobre $RUTA_LOG/$HOST";

                time perl $RUTA/bin/$PROGRAMA $RUTA
                echo "Ejecución completada (OK)."
                echo ""

                if  [ "$PROGRAMA" != "adas.pl" ]; then
                        mv $RUTA_LOG/$HOST.actual $RUTA_LOG/$HOST
                        rm $RUTA/log/temp
                fi
        done

        date

) 9> "$LOCK_FILE"
