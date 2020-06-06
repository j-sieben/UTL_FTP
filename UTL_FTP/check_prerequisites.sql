
declare
  l_is_installed pls_integer;
begin
  select count(*)
    into l_is_installed
	from dba_objects
   where owner = '&INSTALL_USER.'
     and object_type in ('PACKAGE', 'SYNONYM')
	 and object_name in ('PIT', 'PIT_ADMIN');
  if l_is_installed = 0 then
    raise_application_error(-20000, 'Installation of PIT is required to install UTL_FTP. You can download PIT from GIT_HUB as well.');
  else
    dbms_output.put_line('&s1.Installation prerequisites checked succesfully.');
  end if;
end;
/
