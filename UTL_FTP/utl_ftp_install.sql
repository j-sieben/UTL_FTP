/* Script to install UTL_FTP
 * parameter INSTALL_USER: User to install UTL_FTP to
 * parameter DEFAULT_LANGUAGE: Default language of the PIT installation
 */

@init.sql

define sql_dir=sql/
define plsql_dir=plsql/
define msg_dir =messages/&DEFAULT_LANGUAGE./


alter session set current_schema=&INSTALL_USER.;

prompt
prompt &h1.Installing UTL_FTP
prompt &h2.Check installation prerquisites
@check_prerequisites.sql
@check_user_exists.sql

prompt &h2.Remove existing installation
@clean_up_install.sql

alter session set current_schema=&INSTALL_USER.

prompt &h2.Create tables and initial data
prompt &s1.Create table FTP_SERVER
@&sql_dir.table/ftp_server.tbl

prompt &h2.Create type declarations
prompt &s1.Create type FTP_LIST_T
@&sql_dir.type/ftp_list_t.tps
show errors

prompt &s1.Create type FTP_LIST_TAB
@&sql_dir.type/ftp_list_tab.tps
show errors

prompt &s1.Create type FTP_REPLY_T
@&sql_dir.type/ftp_reply_t.tps
show errors

prompt &s1.Create type FTP_REPLY_TAB
@&sql_dir.type/ftp_reply_tab.tps
show errors

prompt &s1.Create type CHAR_TABLE
@&sql_dir.type/char_table.tps
show errors

prompt &h2.Create package declarations
prompt &s1.Create package UTL_FTP
@&plsql_dir.utl_ftp.pks
show errors

prompt &s1.Create package UTL_FTP
@&plsql_dir.utl_ftp.pks
show errors

prompt &h2.Create messages
@&msg_dir.MessageGroup_UTL_FTP.sql

prompt &h2.Create type bodies
prompt &s1.Create type body FTP_LIST_T
@&sql_dir.type/ftp_list_t.tpb
show errors

prompt &h2.Create package bodies
prompt &s1.Create package body UTL_FTP
@&plsql_dir.utl_ftp.pkb
show errors