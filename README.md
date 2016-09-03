# UTL_FTP
Simple FTP client for in database use

## What it is
Based on the work of Tim Hall at [Oracle Base](https://oracle-base.com/articles/misc/ftp-from-plsql) I started to build my own implementation of a FTP client for in database use. The work of Tim was extremely useful as it showed me how talking to a FTP server can be done. But it turned out that I needed a different interface and some additional functionality over what Tim has implemented. I therefore decided to extend Tim's code but soon it turned out that I had to completely redesign it in order to achieve my requirements. These are:

- Ability to directly send a blob or clob from within the database to a FTP server and receive a FTP file into a BLOB or CLOB directly
- Being able to work within a session without having to re-connect each time
- Ability to read a FTP directory directly from within SQL and use this within a cursor in PL/SQL
- Searching through directory structures with SQL
- Full instrumentation, including exception handling

All this is now possible with `UTL_FTP`. I want to give back to the community what I took by reading and understanding Tim's code, so here is my implementation, free to use for anybody who feels a requirement to use it.

## How it works

Basically you can work with `UTL_FTP` in two ways: With explicit or implicit session.

You start by registering a FTP server with `UTL_FTP` by providing the package the credentials of that server and a nickname for it. If you like, you can have `UTL_FTP` store these credentials in a database table for you, or you can pass the credentials in for one explicit session and have `UTL_FTP` discard it later.

Here's an example of how to register a FTP server with `UTL_FTP`:

```
begin
  utl_ftp.register_ftp_server(
    p_ftp_server => 'FOO', -- this is the nickname you reference the server with
    p_host_name => '129.168.1.10', -- or DNS name
    p_port => 21,
    p_username => 'FOO', -- defaults to anonymous
    p_password => 'my_pass',
    p_permanent => true -- this controls whether the credentials get stored or not
  );
end;
```

Once a FTP server is registered, you can either explicitly create a session or simply use `UTL_FTP` directly. Here's an example of how you could query a directory on the server in plain SQL with and implicit session:

```
SQL> select item_name, item_type, item_modify_date, file_size
  2    from table(utl_ftp.list_directory('/Users/j.sieben/Desktop', 'FOO'))
  3   where item_type = 'file'
  4     and item_name like '%sql';

ITEM_NAME                      ITEM_TYPE            ITEM_MOD  FILE_SIZE
------------------------------ -------------------- -------- ----------
f133.sql                       file                 27.07.16     698723
f179.sql                       file                 03.08.16     403890
```

You see that `UTL_FTP.list_directory` implicitly connected to server `FOO` based on the credentials you passed in when registring the server. It also logged out automatically after having received all information, in this case from command `MLSD /Users/j.sieben/Desktop`. Here you see the advantage of having the directory available in SQL, as you can deliberately filter and search using plain SQL.

The second basic usage is to explicitly create a session and issue one or more commands afterwards. In this case, the session keeps open until you explicitly log off again, saving resources and enhancing speed. As FTP dictates, each command will use it's own control connection to read data if required, but the data connection keeps open until you log off. Here's an example of that usage:

```
begin
  utl_ftp.login('FOO');
  utl_ftp.create_directory('/Users/j.sieben/Desktop/Archive');
  utl_ftp.rename_file('/Users/j.sieben/Desktop/Testfile.txt', '/Users/j.sieben/Desktop/Archive/Testfile.txt');
  utl_ftp.delete_file('/Users/j.sieben/Desktop/Archive/Testfile.txt');
  utl_ftp.remove_directory('/Users/j.sieben/Desktop/Archive');
  utl_ftp.logout;
end;
/
```

`UTL_FTP` uses [PIT](https://github.com/j-sieben/PIT) under the covers to log any response to commands. Here's the full log for the above action:

```
> UTL_FTP.login
..> UTL_FTP.get_ftp_server
..< UTL_FTP.get_ftp_server [wc=03.09.16 19:04:21,575000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
..> UTL_FTP.login
....> UTL_FTP.get_response
--> Antwort: 220 192.168.1.33 FTP server (tnftpd 20100324+GSSAPI) ready.
......> UTL_FTP.check_response
--> OK
......< UTL_FTP.check_response [wc=03.09.16 19:04:21,606000; e=2; e_cpu=2; t=+00 00:00:00.016000; t_cpu=2]
....< UTL_FTP.get_response [wc=03.09.16 19:04:21,606000; e=4; e_cpu=2; t=+00 00:00:00.031000; t_cpu=2]
....> UTL_FTP.do_command
......> UTL_FTP.get_response
--> Antwort: 331 User j.sieben accepted, provide password.
........> UTL_FTP.check_response
--> OK
........< UTL_FTP.check_response [wc=03.09.16 19:04:21,606000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
......< UTL_FTP.get_response [wc=03.09.16 19:04:21,606000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
....< UTL_FTP.do_command [wc=03.09.16 19:04:21,606000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
....> UTL_FTP.do_command
......> UTL_FTP.get_response
--> Antwort: 230 User j.sieben logged in.
........> UTL_FTP.check_response
--> OK
........< UTL_FTP.check_response [wc=03.09.16 19:04:21,716000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
......< UTL_FTP.get_response [wc=03.09.16 19:04:21,716000; e=22; e_cpu=0; t=+00 00:00:00.110000; t_cpu=0]
....< UTL_FTP.do_command [wc=03.09.16 19:04:21,716000; e=11; e_cpu=0; t=+00 00:00:00.110000; t_cpu=0]
..< UTL_FTP.login [wc=03.09.16 19:04:21,716000; e=20; e_cpu=6; t=+00 00:00:00.141000; t_cpu=2]
< UTL_FTP.login [wc=03.09.16 19:04:21,716000; e=14; e_cpu=2; t=+00 00:00:00.141000; t_cpu=2]
> UTL_FTP.create_directory
..> UTL_FTP.auto_login
..< UTL_FTP.auto_login [wc=03.09.16 19:04:21,716000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
..> UTL_FTP.do_command
....> UTL_FTP.get_response
--> Antwort: 257 "/Users/j.sieben/Desktop/Archive" directory created.
......> UTL_FTP.check_response
--> OK
......< UTL_FTP.check_response [wc=03.09.16 19:04:21,716000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
....< UTL_FTP.get_response [wc=03.09.16 19:04:21,716000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
..< UTL_FTP.do_command [wc=03.09.16 19:04:21,716000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
..> UTL_FTP.auto_logout
No auto session detected.
..< UTL_FTP.auto_logout [wc=03.09.16 19:04:21,716000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
< UTL_FTP.create_directory [wc=03.09.16 19:04:21,716000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
> UTL_FTP.rename_file
..> UTL_FTP.auto_login
..< UTL_FTP.auto_login [wc=03.09.16 19:04:21,716000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
..> UTL_FTP.do_command
....> UTL_FTP.get_response
--> Antwort: 350 File exists, ready for destination name
......> UTL_FTP.check_response
--> OK
......< UTL_FTP.check_response [wc=03.09.16 19:04:21,731000; e=1; e_cpu=1; t=+00 00:00:00.015000; t_cpu=1]
....< UTL_FTP.get_response [wc=03.09.16 19:04:21,731000; e=1; e_cpu=1; t=+00 00:00:00.015000; t_cpu=1]
..< UTL_FTP.do_command [wc=03.09.16 19:04:21,731000; e=1; e_cpu=1; t=+00 00:00:00.015000; t_cpu=1]
..> UTL_FTP.do_command
....> UTL_FTP.get_response
--> Antwort: 250 RNTO command successful.
......> UTL_FTP.check_response
--> OK
......< UTL_FTP.check_response [wc=03.09.16 19:04:21,731000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
....< UTL_FTP.get_response [wc=03.09.16 19:04:21,731000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
..< UTL_FTP.do_command [wc=03.09.16 19:04:21,731000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
..> UTL_FTP.auto_logout
No auto session detected.
..< UTL_FTP.auto_logout [wc=03.09.16 19:04:21,731000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
< UTL_FTP.rename_file [wc=03.09.16 19:04:21,731000; e=3; e_cpu=3; t=+00 00:00:00.015000; t_cpu=1]
> UTL_FTP.delete_file
..> UTL_FTP.auto_login
..< UTL_FTP.auto_login [wc=03.09.16 19:04:21,731000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
..> UTL_FTP.do_command
....> UTL_FTP.get_response
--> Antwort: 250 DELE command successful.
......> UTL_FTP.check_response
--> OK
......< UTL_FTP.check_response [wc=03.09.16 19:04:21,731000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
....< UTL_FTP.get_response [wc=03.09.16 19:04:21,731000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
..< UTL_FTP.do_command [wc=03.09.16 19:04:21,731000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
..> UTL_FTP.auto_logout
..< UTL_FTP.auto_logout [wc=03.09.16 19:04:21,731000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
< UTL_FTP.delete_file [wc=03.09.16 19:04:21,731000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
> UTL_FTP.remove_directory
..> UTL_FTP.auto_login
..< UTL_FTP.auto_login [wc=03.09.16 19:04:21,731000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
..> UTL_FTP.do_command
....> UTL_FTP.get_response
--> Antwort: 250 RMD command successful.
......> UTL_FTP.check_response
--> OK
......< UTL_FTP.check_response [wc=03.09.16 19:04:21,731000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
....< UTL_FTP.get_response [wc=03.09.16 19:04:21,731000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
..< UTL_FTP.do_command [wc=03.09.16 19:04:21,731000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
..> UTL_FTP.auto_logout
..< UTL_FTP.auto_logout [wc=03.09.16 19:04:21,731000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
< UTL_FTP.remove_directory [wc=03.09.16 19:04:21,731000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
> UTL_FTP.logout
..> UTL_FTP.do_command
....> UTL_FTP.get_response
--> Antwort: 221 
......> UTL_FTP.check_response
--> OK
......< UTL_FTP.check_response [wc=03.09.16 19:04:21,746000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
....< UTL_FTP.get_response [wc=03.09.16 19:04:21,746000; e=0; e_cpu=0; t=+00 00:00:00.000000; t_cpu=0]
..< UTL_FTP.do_command [wc=03.09.16 19:04:21,746000; e=4; e_cpu=4; t=+00 00:00:00.015000; t_cpu=2]
< UTL_FTP.logout [wc=03.09.16 19:04:21,746000; e=2; e_cpu=2; t=+00 00:00:00.015000; t_cpu=2]
```

Or, here's the output of `utl_ftp.get_control_log` which is available within an explicit session:

```
...
for r in (select code || ': ' || message reply 
            from table(utl_ftp.get_control_log)) loop
  dbms_output.put_line(r.reply);
end loop;
...

REPLY
--------------------------------------------------------------
220: 192.168.1.33 FTP server (tnftpd 20100324+GSSAPI) ready.
331: User j.sieben accepted, provide password.
230: User j.sieben logged in.
257: "/Users/j.sieben/Desktop/Archive" directory created.
350: File exists, ready for destination name
250: RNTO command successful.
250: DELE command successful.
250: RMD command successful.
```

## Supported commands

Basically, `UTL_FTP` is easy to extend beyond the functionality implemented now. Here's a list of the method `UTL_FTP` provides:

- get (overloaded for file to file, file to blob or file to clob)
- put (overloaded for file to file, blob to file or clob to file)
- list_directory (MSLD, accessible via a pipelined function and converted to an object for easy access)
- create/remove_directory
- create/rename/copy/delete_file
- get_server_status
- get_control_log (all response codes from a complete session)
- get_help (for a specific command or generically, not converted, simple raw text output as pipelined function)

To extend this, you simply add a method to the package. Here's an example method that implements creating a directory:

```
procedure create_directory(
  p_directory in varchar2,
  p_ftp_server in varchar2 default null) 
as
  l_ftp_server ftp_server_rec;
begin
  pit.enter_mandatory('create_directory', c_pkg);
  auto_login(p_ftp_server);
  do_command(trim(c_ftp_make_directory || p_directory), code_tab(257));
  auto_logout;
  pit.leave_mandatory;
exception
  when others then
    auto_logout;
    pit.stop(msg.SQL_ERROR, msg_args(sqlerrm));
end create_directory;
```
