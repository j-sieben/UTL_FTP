create or replace package utl_ftp 
  authid definer
as
  -- --------------------------------------------------------------------------
  -- Name         : https://oracle-base.com/dba/miscellaneous/ftp.pks
  -- Author       : Tim Hall
  -- Description  : Basic FTP API. For usage notes see:
  --                  https://oracle-base.com/articles/misc/ftp-from-plsql.php
  -- Requirements : UTL_TCP
  -- --------------------------------------------------------------------------
  
  c_type_binary constant char(1 byte) := 'I';
  c_type_ascii constant char(1 byte) := 'A';

  /* AUTHENTICATION */
  /* Method to register a server explicitly at the package
   * %param p_ftp_server Nickname of the server, referenced in subsequent calls.
   *        Limit of 30 byte, stored in uppercase
   * %param p_host_name Name or IP address of the FTP server
   * %param p_port Port of the FTP server. Defaults to 21
   * %param p_username Username of the account. Defaults to 'anonymous'
   * %param p_password Password, defaults to FOO
   * %param p_permanent If TRUE, the registration is stored at FTP_SERVER and
   *        automatically registered from thereon
   * %usage Is called to explicitly register a FTP server. Alternatively, it may
   *        be written to table FTP_SERVERS to allow for automatic registration
   *        upon initialization of the package.
   *        CAUTION: Nicknames are unique and case insensitive.
   *        A server with the same nickname as an existing server will be 
   *        overwritten with the respective settings. 
   *        The user is responsible to take care of uniqueness and correct use!
   */
  procedure register_ftp_server(
    p_ftp_server in varchar2,
    p_host_name in varchar2,
    p_port in varchar2 default '21',
    p_user_name in varchar2 default 'anonymous',
    p_password in varchar2 default 'foo',
    p_permanent in boolean default true);
    
    
  /* Method to un-register a registered server from the server list
   * %param p_ftp_server Nickname of the server to unregister
   * %usage This method will un-register the FTP server both from the actual
   *        instance as well as from table FTP_SERVER.
   *        It will not unregister the server from other instances of this package
   *        running in different sessions.
   */
  procedure unregister_ftp_server(
    p_ftp_server in varchar2);
    
    
  /* Method to explicitly start a FTP session
   * %param p_ftp_server Nickname of the registered FTP server to connect to
   * %usage All commands have an auto logon option that enables them to automatically
   *        connect and disconnect to a registered FTP server.
   *        Disadvantage is that these methods open and close a session per call.
   *        If you want to issue more than one command using the same session, you
   *        may explicitly open a connection for this server and close it after the
   *        chain of commands using method LOGOUT.
   */
  procedure login(
    p_ftp_server in varchar2);
    
    
  /* Method to close an explicitly opened FTP session
   * %usage Called to finish the explicit FTP session opened by LOGIN.
   *        Please make sure to explicitly close all explicitly opened sessions
   *        to avoid denial of service due to max open session exceeded
   */
  procedure logout;

    
  /* COMMANDS */
  /* Procedure to read a file from the FTP server and copy it to the local filesystem
   * %param p_ftp_server Nickname of the registered server to read from
   * %param p_from_file Name of the file to retrieve
   * %param p_to_directory Name of an oracle directory to store the file at
   * %param p_to_file local file name
   * %param p_transfer_type Type of data transfer. Choose between BINARY and ASCII.
   *        Defaults to BINARY
   * %usage This overloaded method shall be used if a file from the FTP server is
   *        to be copied to a local file system. If you want to consume the content
   *        within the database, select the other overloaded methods to directly
   *        return CLOB or BLOB
   */
  procedure get(
    p_from_file in varchar2,
    p_to_directory in varchar2,
    p_to_file in varchar2,
    p_ftp_server in varchar2 default null,
    p_transfer_type in varchar2 default c_type_binary);
    
    
  /* Overloaded method to read a file from an FTP server to a local CLOB
   * %param p_ftp_server Nickname of the registered server to read from
   * %param p_from_file Name of the file to retrieve
   * %param p_data Out parameter with the file content as CLOB
   * %param p_transfer_type Optional parameter to choose betwen BINARY or ASCII
   *        file transmission. Defaults to BINARY
   * %usage Use this method if you need to retrieve a file from the FTP server as CLOB
   */
  procedure get(
    p_from_file in varchar2,
    p_data out nocopy clob,
    p_ftp_server in varchar2 default null,
    p_transfer_type in varchar2 default c_type_binary);
    
    
  /* Overloaded method to read a file from an FTP server to a local BLOB
   * %param p_ftp_server Nickname of the registered server to read from
   * %param p_from_file Name of the file to retrieve
   * %param p_data Out parameter with the file content as BLOB
   * %usage Use this method if you need to retrieve a file from the FTP server as BLOB
   */
  procedure get(
    p_from_file in varchar2,
    p_data out nocopy blob,
    p_ftp_server in varchar2 default null);
    
  
  /* Method to copy a local file to the FTP server
   * %param p_ftp_server Nickname of the registered server to write to
   * %param p_from_dir Name of an oracle directory that contains the file to copy
   * %param p_from_file Name of the local file
   * %param p_to_file Path and name of the remote file
   * %param p_transfer_type Type of data transfer (C_TYPE_BINARY|C_TYPE_ASCII),
   *        defaults to C_TYPE_BINARY
   * %usage This overloaded method should be used if you need to copy a local file
   *        to an FTP server. If the data to copy is available as CLOB or BLOB within
   *        the database, use the overloaded versions instead.
   */
  procedure put(
    p_from_directory in varchar2,
    p_from_file in varchar2,
    p_to_file in varchar2,
    p_ftp_server in varchar2 default null,
    p_transfer_type in varchar2 default c_type_binary);
    
    
  /* Method to copy a local CLOB/BLOB instance to a file on the FTP server
   * %param p_ftp_server Nickname of the registered server to write to
   * %param p_to_file Path and name of the file on the FTP server
   * %param p_clob Optional CLOB instance to copy to the FTP server
   * %param p_clob Optional BLOB instance to copy to the FTP server
   * %param p_transfer_type If the CLOB parameter is used, this parameter can
   *        be set to switch transfer mode to BINARY instead of ASCII
   * %usage This method overload is used to store a local CLOB/BLOB instance
   *        at the FTP server.
   *        If neither P_CLOB nor P_BLOB is used, an error is thrown.
   */
  procedure put(
    p_to_file in varchar2,
    p_clob in clob default null,
    p_blob in blob default null,
    p_ftp_server in varchar2 default null,
    p_transfer_type in varchar2 default c_type_ascii);
    
    
  /* Method to pass arbitrary commands to the FTP server (no data transmission)
   * %param p_ftp_server Nickname of the FTP-server
   * %param p_ftp_server Nickname of the FTP-server
   * %usage Called to pass any command to the FTP server
   */
  procedure execute_command(
    p_command in varchar2,
    p_ftp_server in varchar2 default null);
  
  
  /* Method GET_SERVER_STATUS reads the actual status of the FTP server and
   * returns it as an instance of CHAR_TABLE.
   * %param p_ftp_server Nickname of the FTP-server
   * %return Instance of type CHAR_TABLE with the status from the FTP server
   * %usage This method is designed to be used from within SQL in the form
   *        <pre>select * from table(utl_ftp.get_server_status('MY_FTP'));</pre>
   *        Output is meant to be read by humans only, so no processing of the 
   *        response is made.
   *        If used without opening a session prior to this call, it connects
   *        to the server and disconnects after completion automatically.
   *        Only available with explicit sessions, no AUTO LOGIN
   */  
  function get_server_status(
    p_ftp_server in varchar2 default null)
    return char_table pipelined;
    
  
  /* Method to retrieve the control log as a data structure for further reference
   * %usage In an explicit session (explicitly opened by calling LOGON), the
   *        list of responses from the FTP server is collected in a local variable.
   *        It can be retrieved using this method.
   *        Only available with explicit sessions, no AUTO LOGIN
   */
  function get_control_log
    return ftp_reply_tab pipelined;
    
    
  /* Command to retrieve help from the FTP server
   * %param p_ftp_server Nickname of the FTP-server
   * %param p_command Optional name of the command you want to get help for.
   *        If ommited, general help is returned
   * %usage Call this method to retrieve help information from the FTP server.
   *        The output is not processed and intended to be consumed by human
   *        readers only.
   */
  function get_help(
    p_command in varchar2 default null,
    p_ftp_server in varchar2 default null)
    return char_table pipelined;
    
  
  /* Method to retrieve a directory listing of the directory specified
   * %param p_ftp_server Nickname of the FTP-server
   * %param p_directory Optional path to the directory you require a listing for
   *        if ommited, the actual working directory is returned
   * %usage This methods returns a processed version of the MLSD output in that
   *        it extracts the facts into separate columns and makes them accessible
   *        as a SQL table using the table function.
   *        Example: <pre>select * from table(utl_table('MY_FTP', '/path/'));</pre>
   */
  function list_directory(
    p_directory in varchar2 default null,
    p_ftp_server in varchar2 default null)
    return ftp_list_tab pipelined;
  
  
  /* Creates a directory on the FTP server
   * %param p_ftp_server Nickname of the FTP-server
   * %param p_directory Name of the directory to create
   * %usage Is called to create a new directory on the FTP server
   */
  procedure create_directory(
    p_directory in varchar2,
    p_ftp_server in varchar2 default null);
  
  
  /* Removes a directory on the FTP server
   * %param p_ftp_server Nickname of the FTP-server
   * %param p_directory Name of the directory to remove
   * %usage Is called to remove a directory on the FTP server
   */
  procedure remove_directory(
    p_directory in varchar2,
    p_ftp_server in varchar2 default null);
  
  
  /* Renames a file on the FTP server
   * %param p_ftp_server Nickname of the FTP-server
   * %param p_from Name of the existing file
   * %param p_to New name of the file
   * %usage Is called to rename a file on the FTP server
   *        Useful to indicate completion of an upload by renaming the file after
   *        succesful loading (semaphore use).
   *        May be used to copy a file to a new location as well.
   */
  procedure rename_file(
    p_from in varchar2,
    p_to in varchar2,
    p_ftp_server in varchar2 default null);
  
  
  /* Deletes a file from the FTP server
   * %param p_ftp_server Nickname of the FTP-server
   * %param p_file Name of the file to delete
   * %usage Is called to delete a file from the FTP server
   */
  procedure delete_file(
    p_file in varchar2,
    p_ftp_server in varchar2 default null);

end utl_ftp;
/