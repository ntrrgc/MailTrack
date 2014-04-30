<div id="footer-wrapper">

	<div class="center-wrapper">

		<div id="footer">

			<div class="left">
			<a href="<?php echo site_url(''); ?>">Inicio</a> <span class="text-separator">|</span> <a href="<?php echo site_url('mensajes/lista/todos'); ?>">Mis mensajes</a> 

<?php  if ($this->controlacceso->permisoAdministracion()){ ?>
        <span class="text-separator">|</span> <a href="<?php echo site_url('accesos/lista/todos'); ?>">Mis accesos</a>
<?php } ?>

<span class="text-separator">|</span> <a href="<?php echo site_url('buscador'); ?>">Buscador</a>

<?php  if ($this->controlacceso->permisoAdministracion()){ ?>
	<span class="text-separator">|</span> <a href="<?php echo site_url('admin/task'); ?>">Administración</a>
<?php } ?>

 <span class="text-separator">|</span> <a href="<?php echo site_url('ayuda'); ?>">Ayuda</a> <span class="text-separator">|</span> <a href="<?php echo site_url('logout'); ?>">Cerrar sesión</a>
			</div>

			<div class="right">
				<a href="#">Top ^</a>
			</div>
			
			<div class="clearer">&nbsp;</div>

		</div>

	</div>

</div>

<div id="bottom">

	<div class="center-wrapper">

		<div class="left">
		</div>

		<div class="right">

			<a href="http://identidad.usal.es/">Universidad de Salamanca. Servicios Informáticos, C.P.D. servicios.red@usal.es </a>  
		</div>
		
		<div class="clearer">&nbsp;</div>

<?php 
/*
	if ($this->controlacceso->permisoAdministracion()){
		$this->output->enable_profiler(TRUE);
	}
*/
?>

	</div>

</div>

</body>
</html>
