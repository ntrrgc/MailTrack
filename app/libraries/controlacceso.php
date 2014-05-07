<?php
/*
 * Copyright 2010 Víctor Téllez Lozano <vtellez@us.es>
 *
 *    This file is part of Seguimiento.
 *
 *    Seguimiento is free software: you can redistribute it and/or modify it
 *    under the terms of the GNU Affero General Public License as
 *    published by the Free Software Foundation, either version 3 of the
 *    License, or (at your option) any later version.
 *
 *    Seguimiento is distributed in the hope that it will be useful, but
 *    WITHOUT ANY WARRANTY; without even the implied warranty of
 *    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *    Affero General Public License for more details.
 *
 *    You should have received a copy of the GNU Affero General Public
 *    License along with Seguimiento.  If not, see
 *    <http://www.gnu.org/licenses/>.
 */
class Controlacceso {
        private $CI;
        private $o;
        private $identidad=false;

        function Controlacceso() {

                $this->CI =& get_instance();
		$this->identidad = $this->CI->session->userdata('identidad');
        }

        /**
         * Fuerza la autenticación si no se ha producido aún
         */
        function control() {
                require_once(BASEPATH . '../app/config/cas.php');
                require_once(BASEPATH . '../app/libraries/CAS-1.3.2/CAS.php');

                $client = phpCAS::client(CAS_VERSION_2_0, $cas_host, $cas_port, $cas_context);
                phpCAS::setCasServerCACert($cas_server_ca_cert_path);
                phpCAS::forceAuthentication();

                // Si el usuario se ha logeado con una sesión nueva...
                if ($this->CI->session->userdata('identidad') == FALSE) {
                        //incrementamos el número de visitas a la aplicación
                        $this->CI->db->query('UPDATE estadisticas SET visitas = visitas + 1;');

                        //Registramos el acceso en los logs si estaba activa la opción desde config.php
                        if ($this->CI->config->item('admin_log') == "true")
                        {
                                log_message('info', 'Usuario "'.phpCAS::getUser().'" inició sesión en seguimiento."');
                        }
                }

                $attrs = phpCAS::getAttributes();

                $data = array(
                        'identidad' => $attrs['uid'],
                        'uid' => $attrs['uid'],
                        'alias' => phpCAS::getUser(),
                        'mail' => $attrs['mail'],
                        'sexo' => "1",
                );

                // Guardar sesión
                $this->CI->session->set_userdata($data);
                $this->identidad = $data;

                // Si hemos llegado hasta aquí, el usuario está autenticado.
                return TRUE;
        }


        /**
         * Comprueba si el usuario actual tiene permiso de administración
         */

        function permisoAdministracion() {
                $admins = $this->CI->config->item('administradores');

                return in_array($this->identidad['uid'], $admins);
        }

	
	/**
	 * Logout de usuario
	 */

	function logout() {
                phpCAS::logout();
	}

}
