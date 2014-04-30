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
class Mensajes extends CI_Controller {

	function __construct()
	{
		parent::__construct();
                $this->controlacceso->control();
	}
	
	function ver($idmensaje)
	{
         	// comprobamos que el mensaje existe y el usuario actual tiene  permisos para ver dicho mensaje		
		$this->db->where('mid', $idmensaje); 
		$mensajes = $this->db->get('mensajes');

		$cuenta_actual = $this->session->userdata('mail');
		$row = $mensajes->row();
		
		$permiso = false;
		if($mensajes->num_rows())
		{
                        if(strcasecmp($cuenta_actual, $row->mto) == 0 ||
                           strcasecmp($cuenta_actual, $row->mfrom) == 0 ||
                           $this->controlacceso->permisoAdministracion())
			{ 
				$permiso = true; 
			}
		}

		if($permiso)
		{
			$emisor="";
			$destinatario="";

			$patrones = $this->config->item('patrones_para_listas');
			foreach($patrones as $patron){
				if(stristr($row->mfrom, $patron)){
					$emisor="list_";
				}
                                if(stristr($row->mto, $patron)){
                                        $destinatario="list_";
                                }
			}

			$aliases = $this->config->item('aliases_para_listas');
                        foreach($aliases as $alias){
                                if($row->mfrom == $alias){
                                        $emisor="list_";
                                }
                                if($row->mto == $alias){
                                        $destinatario="list_";
                                }
                        }


			$cuenta = $this->session->userdata('mail');
			$sexo = $this->session->userdata('sexo');

			//Comprobamos si el emisor coincide con la cuenta actual y su sexo es femenino
			if( $cuenta == $row->mfrom && $sexo == "2"){ $emisor = "she_";}
			
                        //Comprobamos si el destinatario coincide con la cuenta actual y su sexo es femenino
                        if( $cuenta == $row->mto && $sexo == "2"){ $destinatario = "she_"; }

			//Pasamos también los datos del estado del mensaje:
			$this->db->where('codigo', $row->estado);
			$estados = $this->db->get('estados');	
			$estado = $estados->row();

			//Asi como el historial del mensaje:
			$this->db->where('message_id', $row->message_id);
			$this->db->where('hto', $row->mto);
			$this->db->order_by("estado", "asc"); 
                        $historial = $this->db->get('historial');

			$error = 0;
		}else
		{
			$row = $historial = $estado = null;
			$emisor = $destinatario = "";
		 	$error = 1;
		}
		

                $data = array(
				'error' => $error,
				'mensaje' => $row,
				'emisor' => $emisor,
				'destinatario' => $destinatario,
				'est' => $estado,
				'historial' => $historial,
                                'subtitulo' => 'Vista detalla de mensaje',
                                'controlador' => 'mensajes',
				'parent' => '_parent',
                );
                $this->load->view('cabecera', $data);
		$this->load->view('mensaje.php');
		$this->load->view('pie.php');
	}


	
	function lista($filtro='todos',$campo='fecha',$sentido='desc'){
		/*
		* $campo: Campo de la tabla mensajes por el que ordendar la consulta.
		* $sentido: Sentido (ascendente o descendente) para ordenar la consulta. 
		* $filtro:
		* Calculamos los mensajes a consultar en función del parámetro filtro:
		* todos: Mostramos todos los mensajes (enviados y recibidos) para la cuenta activa
		* recibidos: Mostramos solo los mensajes recibidos en la cuenta activa
		* enviados: Mostramos solos los mensajes enviados en la cuenta activa
		* resultados: Mostramos aquellos mensajes resultantes de la consulta SQL formada a partir de el filtro creado con  buscador. 
		*/
		$cuenta = $this->session->userdata('mail');

                //Cargamos los enlaces a la paginacion
                $this->load->library('pagination');
                $config['per_page'] = $this->config->item('num_item_pagina');
                $config['first_link'] = '&lt;&lt';
                $config['last_link'] = '&gt;&gt;';
		$config['uri_segment'] = 6;
		$config['num_links'] = 2;	
		$config['full_tag_open'] = '<div id="paginacion">';
		$config['full_tag_close'] = '</div>';
		$config['cur_tag_open'] = '<div id="paginacion_actual">';
		$config['cur_tag_close'] = '</div>';

                $query_args = array();

		if($filtro == "recibidos"){

                	$config['base_url'] = site_url("mensajes/lista/recibidos");
                        $where = "mto = ".$this->db->escape($cuenta);
 		
		}elseif ($filtro == "informe"){

                        $config['base_url'] = site_url("mensajes/lista/informe");

			if ($this->session->userdata('where_consulta') != ""){
				$where = $this->session->userdata('where_consulta');
			}else{
                                $where = "(mfrom = ".$this->db->escape($cuenta).
                                         " OR mto = ".$this->db->escape($cuenta).")";
			}
			$informe = 1;

		}elseif ($filtro == "enviados"){	

                	$config['base_url'] = site_url("mensajes/lista/enviados");
			$where = "mfrom = ".$this->db->escape($cuenta);

		}elseif ($filtro == "resultados"){

			$this->load->library('session');
		
                	$config['base_url'] = site_url("mensajes/lista/resultados");

			//Procesamos la consulta de la búsqueda
			if(!isset($_POST['oculto'])){
				$where = $this->session->userdata('where_consulta');
				if($where == ""){
					redirect(site_url('buscador'), 'refresh');
				}
			
			}else{
				$where = "mid > 0";
	
				if($_POST['mfrom'] != ""){
					$cadena = str_replace("*", "%", $_POST['mfrom']);
                                        $cadena = str_replace("?", "_", $cadena);
					$where .= " AND mfrom LIKE ".$this->db->escape($cadena);
				}

                        	if($_POST['mto'] != ""){
                                        $cadena = str_replace("*", "%", $_POST['mto']);
                                        $cadena = str_replace("?", "_", $cadena);
					$where .= " AND mto LIKE ".$this->db->escape($cadena);
				}
                        
				if($_POST['message_id'] != "")
				{
                                        $where .= " AND message_id = ".
                                                $this->db->escape($_POST['message_id']);
				}
                        
	                        if($_POST['estado'] != "0")
				{
                                        if (preg_match('/^[<>=] \d+( AND estado < 400)?$/', $_POST['estado'])) {
                                                $where .= " AND estado ".$_POST['estado'];
                                        } else {
                                                /* Break-in attempt */
                                        }
				}
		
				if($_POST['asunto'] != ""){
					if($_POST['condicion_asunto'] == "es"){
						$where .= " AND asunto = ".$this->db->escape($_POST['asunto']);
					}else{
						if($_POST['condicion_asunto'] == "contiene_todas"){
							$op = " AND ";
						}else{
							$op = " OR ";
						}
						$palabras = explode(" ", trim($_POST['asunto']));
                                                $palabras_like = array();
                                                foreach ($palabras as $pal) {
                                                        $pal_like = $this->db->escape_like_str($pal);
                                                        $palabras_like[] = "asunto LIKE '%" . $pal_like . "%'";
                                                }
                                                $where .= " AND (" . implode($op, $palabras_like) . ")";
					}
				}

                                /* Dead code?
                                 
                                if($_POST['historial'] != "")
                                {
					$cadena = str_replace("*", "%", $_POST['historial']);
                                        $cadena = str_replace("'", "\'", $cadena);
                                        $cadena = str_replace(";", "", $cadena);
                                        $cadena = str_replace("--", "", $cadena);
                                        $where = $where." AND virus LIKE '$cadena' ";
                                } */

                                if($_POST['fecha1'] != "Cualquier fecha"){
                                        $fecha1 = strtotime($_POST['fecha1']);
                                        if ($fecha1) {
                                                $where .= " AND fecha <= ".$this->db->escape($fecha1);
                                        } else {
                                                /* Invalid date, suspicious */
                                        }
				}

                                if($_POST['fecha2'] != "Cualquier fecha"){
                                        $fecha2 = strtotime($_POST['fecha2']);
                                        if ($fecha2) {
                                                $fecha2 += 86400; // end of the day
                                                $where .= " AND fecha <= ".$this->db->escape($fecha2);
                                        } else {
                                                /* Invalid date, suspicious */
                                        }
				}

				//Si el usuario no es admin, solo podrá consultar SUS mensajes
				if (!$this->controlacceso->permisoAdministracion()) {
                                        $where .= " AND (mto = ".$this->db->escape($cuenta)." OR ".
                                                        "mfrom = ".$this->db->escape($cuenta).")";
		                }

				//Incrementamos el número de búsquedas realizadas en la aplicación
				$this->db->query('UPDATE estadisticas SET busquedas = busquedas + 1;');
				
                	}        		
		}else{
			//Solo nos queda la opción de todos los mensajes
                	$config['base_url'] = site_url("mensajes/lista/todos");
			$filtro = "todos";
			$where = "(mto = ".$this->db->escape($cuenta)." OR ".
                                 "mfrom = ".$this->db->escape($cuenta).")";
		}

                //Registramos la consulta del administrador si fue una búsqueda y si estaba activa la opción desde config.php
		if (($this->controlacceso->permisoAdministracion()) && ($this->config->item('admin_log') == "true") && ($filtro == "resultados"))
		{
			if(strpos($where, $this->session->userdata('identidad')) == false)
			{
				log_message('info', 'Usuario administrador "'.$this->session->userdata('identidad').'" consultó: "where '.$where.'"');
			}
		}

                //Guardamos la consulta en la sesion del usuario:
                $this->session->set_userdata('where_consulta', $where);

		$base = $config['base_url'];
		$config['base_url'] = $config['base_url']."/$campo/$sentido/";

		if($sentido == "desc") { $contrario = "asc"; } else { $contrario = "desc"; }
		
		$this->db->where($where);
		$this->db->order_by($campo, $sentido);
		$mensajes = $this->db->get('mensajes',$config['per_page'], (int)$this->uri->segment(6));
		
		$this->db->where($where);

		$totales = $this->db->get('mensajes');
                $config['total_rows'] = $totales->num_rows();
                $num_rows =  $config['total_rows'];  
   
	        $this->pagination->initialize($config);

	
		//Si el usuario NO es administrador y el número de mensajes
		//obtenido es mayor que el total de sus mensajes, registramos un error de seguridad
		$error = 0;
		if (!$this->controlacceso->permisoAdministracion())
                {
			$where_usuario = "(mto = ".$this->db->escape($cuenta)." OR ".
                                         "mfrom = ".$this->db->escape($cuenta).")";
	                $this->db->where($where_usuario);
	                $user = $this->db->get('mensajes');
        	        $totales_usuario = $user->num_rows();

                        if($num_rows > $totales_usuario)
                        {
				$error = 1;
                        	log_message('warning', 'Usuario "'.$this->session->userdata('identidad').'" intentó obtener mensajes no permitidos: '.$where.'"');
                        }
                }	

			
		$data = array(
				'mensajes' => $mensajes,
                                'pagination' => $this->pagination,
				'campo' => $campo,
				'sentido' => $sentido,
				'contrario' => $contrario,
				'base' => $base,
				'num_rows' => $num_rows,
				'parent' => '_parent',
				'subtitulo' => 'Lista de mensajes',
                                'controlador' => 'mensajes',
				'filtro' => $filtro,
				'js_adicionales' => array(
                                ),
                );

                $this->load->view('cabecera', $data);

		if($error == 1)
		{
			$this->load->view('search_error.php',$data);
		}
		else
		{
			if(isset($informe)){
				$this->load->view('informe.php',$data);
				$this->db->query('UPDATE estadisticas SET informes = informes + 1;');
			}else{
	        	        $this->load->view('lista_mensajes.php',$data);
			}
		}
                
		$this->load->view('pie.php');
	}
}
