create or replace package body utl_ftp as
  -- --------------------------------------------------------------------------
  -- Name         : UTL_FTP
  -- Author       : Juergen Sieben, based on the work of Tim Hall
  -- Description  : Basic utl_ftp API.
  -- --------------------------------------------------------------------------
  
  c_pkg constant varchar2(30 byte) := $$PLSQL_UNIT;
  c_cr constant varchar2(2 byte) := chr(13);
  c_chunk_size constant number := 32767;
  c_write_byte constant varchar2(2) := 'wb';
  c_write_text constant varchar2(2) := 'w';
  
  -- FTP commands
  c_ftp_delete constant varchar2(10) := 'DELE ';
  c_ftp_help constant varchar2(10) := 'HELP ';
  c_ftp_list constant varchar2(10) := 'MLSD ';
  c_ftp_make_directory constant varchar2(10) := 'MKD ';
  c_ftp_noop constant varchar2(10) := 'NOOP';
  c_ftp_password constant varchar2(10) := 'PASS ';
  c_ftp_passive constant varchar2(10) := 'PASV';
  c_ftp_quit constant varchar2(10) := 'QUIT';
  c_ftp_retrieve constant varchar2(10) := 'RETR ';
  c_ftp_remove_directory constant varchar2(10) := 'RMD ';
  c_ftp_rename_from constant varchar2(10) := 'RNFR ';
  c_ftp_rename_to constant varchar2(10) := 'RNTO ';
  c_ftp_status constant varchar2(10) := 'STAT';
  c_ftp_store constant varchar2(10) := 'STOR ';
  c_ftp_transfer_ascii constant varchar2(20) := 'TYPE ' || c_type_ascii;
  c_ftp_transfer_binary constant varchar2(20) := 'TYPE ' || c_type_binary;
  c_ftp_user_name constant varchar2(10) := 'USER ';
  
  -- FTP return codes
  c_ftp_transient_error constant char(2 byte) := '4%';
  c_ftp_permanent_error constant char(2 byte) := '5%';
  
  -- Subtypes to easily adopt different chunk sizes
  subtype chunk_type is varchar2(32767);
  subtype raw_chunk_type is raw(32767);
  
  g_binary boolean := true;
  g_open_mode varchar2(2 byte) := c_write_byte;
  
  -- Data structure to keep internal list of ftp-servers accessible via nickname
  type ftp_server_rec is record(
    host_name varchar2(50 char),
    port number,
    user_name varchar2(100 char),
    password varchar2(100 char),
    control_connection utl_tcp.connection,
    data_connection utl_tcp.connection,
    control_reply ftp_reply_tab,
    data_reply ftp_reply_tab,
    auto_session boolean := false);
  type server_list_tab is table of ftp_server_rec index by varchar2(30 byte);
  g_server_list server_list_tab;
  
  g_server ftp_server_rec;
  
  -- Table to pass list of expected result codes to READ_RESPONSE
  type code_tab is table of number(3);

  /* HELPER */ 
  /* Administration of REPLY lists */
  /* Method to push an entry to the respective list
   * %param p_list List of reply records
   * %param p_entry Reply to push to the list
   * %usage Is called internally to store all replies (control and data connection)
   *        for later reference.
   */
  procedure push_list(
    p_list in out nocopy ftp_reply_tab,
    p_entry ftp_reply_t)
  as
  begin
    if p_list is null then
      p_list := ftp_reply_tab();
    end if;
    p_list.extend;
    p_list(p_list.last) := p_entry;
    pit.debug(msg.FTP_RESPONSE_RECEIVED, msg_args(to_char(p_entry.code), p_entry.message));
  end push_list;
  
  
  /* Method to access last entry in reply list
   * %param p_list Reply list
   * %return last entry of reply list
   * %usage used internally to access last response code
   */
  function get_last(
    p_list in ftp_reply_tab)
    return ftp_reply_t
  as
  begin
    return p_list(p_list.last);
  end get_last;
  
  /* Method to analyze output of MLSD-command and convert it to FTP_LIST_T
   * %param p_entry Response of the FTP-server on MLSD command
   * %return Instance of FTP_LIST_T
   * %usage Method uses externally defined FTP_LIST_T to enable access to
   *        the converted answer via SQL and a pipelined function.
   */
   function convert_directory_list(
    p_entry in varchar2)
    return ftp_list_t
  as
    l_key varchar(100);
    l_value varchar2(2000);
    l_ftp_list ftp_list_t;
    l_entry varchar2(32767);
  begin
    pit.enter_detailed('convert_directory_list', c_pkg);
    l_ftp_list := ftp_list_t();
    -- extract file/folder name from response
    l_ftp_list.item_name := regexp_substr(p_entry, '[^\ ]+', 1, 2);
    -- separate other entries in response from name
    l_entry := regexp_substr(p_entry, '[^\ ]+', 1, 1);
    -- extract key value pairs from response and assign values to object attributes
    for i in 1 .. regexp_instr(p_entry, '=') * 2 loop
      if mod(i, 2) = 1 then
        l_key := regexp_substr(l_entry, '[^=;]+', 1, i);
        l_value := regexp_substr(l_entry, '[^=;]+', 1, i+1);
        case upper(l_key)
        when 'TYPE' then l_ftp_list.item_type := l_value;
        when 'MODIFY' then l_ftp_list.item_modify_date := to_date(l_value, 'YYYYMMDDHH24MISS');
        when 'CREATE' then l_ftp_list.item_creation_date := to_date(l_value, 'YYYYMMDDHH24MISS');
        when 'SIZE' then l_ftp_list.file_size := to_number(l_value);
        when 'UNIQUE' then l_ftp_list.item_id := l_value;
        when 'PERM' then l_ftp_list.item_permission := l_value;
        when 'LANG' then l_ftp_list.file_language := l_value;
        when 'MEDIA-TYPE' then l_ftp_list.file_media_type := l_value;
        when 'CHARSET' then l_ftp_list.char_set := l_value;
        else
          null;
        end case;
      end if;
    end loop;
    
    pit.leave_detailed;
    return l_ftp_list;
  exception
    when others then
      pit.leave_detailed;
      raise;
  end;
  
  
  procedure check_response(
    p_expected_code in code_tab,
    p_reply in ftp_reply_t)
  as
    l_ok boolean := false;
  begin
    pit.enter_detailed('check_response', c_pkg);
    -- check permanent and transient errors, expected outcome
    case
    when p_reply.code in (421, 425, 426, 430, 434, 450, 451, 452) then
      pit.error(msg.FTP_TRANSIENT_ERROR, msg_args(p_reply.message));
    when p_reply.code in (501, 502, 503, 504, 530, 532, 534, 550, 551, 552, 553) then
      pit.fatal(msg.FTP_PERMANENT_ERROR, msg_args(p_reply.message));
    else
      if p_expected_code is not null then
        for i in p_expected_code.first .. p_expected_code.last loop
          if p_expected_code(i) = p_reply.code then
            l_ok := true;
            exit;
          end if;
        end loop;
        if l_ok then
          pit.verbose(msg.FTP_RESPONSE_EXPECTED);
        else
          pit.verbose(msg.FTP_UNEXPECTED_RESPONSE, msg_args(to_char(p_reply.code), p_reply.message));
        end if;
      end if;
    end case;
    pit.leave_detailed;
  exception
    when others then
      pit.leave_detailed;
      raise;
  end check_response;
  
  
  /* Method to read output of the control connection
   * %param p_ftp_server reference to the actual ftp server
   * %usage Copies all output of control connection into CONTROL_REPLY attribute.
   * %usage called internally to read output of control connection and pass it
   *        to the calling envorinment, e.g. as a pipelined function
   */
  procedure get_response(
    p_command in varchar2,
    p_expected_code in code_tab)
  as
    l_response varchar2(32767);
    l_reply ftp_reply_t;
  begin
    pit.enter_detailed('get_response', c_pkg);
    if utl_tcp.available(g_server.control_connection, 0.5) > 0 then
      l_response := utl_tcp.get_line(g_server.control_connection, true);
      -- render response and push to list
      if regexp_like(l_response, '^[0-9]{3}') then
        l_reply := ftp_reply_t(to_number(substr(l_response, 1, 3)), substr(l_response, 5));
        push_list(g_server.control_reply, l_reply);
        check_response(p_expected_code, l_reply);
      end if;
    else
      pit.warn(msg.FTP_NO_RESPONSE, msg_args(p_command));
    end if;
    pit.leave_detailed;
  exception
    when msg.FTP_TRANSIENT_ERROR_ERR or msg.FTP_PERMANENT_ERROR_ERR then
      pit.stop;
    when others then
      pit.stop(msg.sql_error, msg_args(sqlerrm));
  end get_response;
  
  
  /* Method to read output of the data connection
   * %usage Copies all output of control connection into DATA_REPLY attribute.
   * %usage called internally to read output of control connection and pass it
   *        to the calling envorinment, e.g. as a pipelined function
   */
  procedure read_reply(
    p_command in varchar2)
  as
    l_reply ftp_reply_t;
  begin
    pit.enter_detailed('read_reply', c_pkg);
    -- designed as a basic loop to allow for reporting of unnecessary calls
    loop
      begin
        if utl_tcp.available(g_server.data_connection, 0.5) > 0 then
          l_reply := ftp_reply_t(null, utl_tcp.get_line(g_server.data_connection, true));
          push_list(g_server.data_reply, l_reply);
        else
          pit.warn(msg.FTP_NO_RESPONSE, msg_args(p_command));
          exit;
        end if;
      exception
        when utl_tcp.end_of_input then
          exit;
      end;
    end loop;
    pit.enter_detailed;
  exception
    when others then
      pit.leave_detailed;
      raise;
  end read_reply;
  
  
  /* Method to send a ftp command
   * %param p_command FTP command to execute
   * %param p_expected_code Optional list of expected results. Used for cross check
   * %usage Called internally to execute a FTP comman at the actually selected FTP server
   */
  procedure do_command(
    p_command in varchar2,
    p_expected_code in code_tab default null) 
  as
    l_result pls_integer;
  begin
    pit.enter_detailed('do_command', c_pkg, 
      msg_params(msg_param('p_command', p_command)));
    l_result := UTL_TCP.write_text(
                  g_server.control_connection, 
                  p_command || utl_tcp.crlf, 
                  length(p_command || utl_tcp.crlf));
    get_response(p_command, p_expected_code);
    pit.leave_detailed;
  exception
    when others then
      pit.leave_detailed;
      raise;
  end do_command;
  
  
  /* Method to get a passive data connection to the FTP server
   * %usage Sets data connection for the actually selected FTP server
   */
  procedure get_data_connection
  as
    l_message varchar2(25);
    l_port number(10);
  begin
    pit.enter_detailed('get_data_connection', c_pkg);
    do_command(c_ftp_passive, code_tab(227));
    
    -- Get port number from response
    l_message := regexp_substr(get_last(g_server.control_reply).message, '[^\(\)]+', 1, 2);
    l_port := regexp_substr(l_message, '[^\,]+', 1, 5) * 256 + regexp_substr(l_message, '[^\,]+', 1, 6);
    
    -- open data connection
    g_server.data_connection := 
      utl_tcp.open_connection(
        remote_host => g_server.control_connection.remote_host, 
        remote_port => l_port);
    pit.leave_detailed;
  exception
    when others then
      pit.leave_detailed;
      raise;
  end get_data_connection;
 
 
  /* Method to issue a command and read data from the data connection
   * %param p_command Command to execute
   * %param p_expected_code Optional list of result codes expected on the control connection
   * %usage Called internally to execute P_COMMAND and read data from data connection.
   *        Flow:
   *        - Open data connection
   *        - Issue command over control connection and check return code
   *        - read data from data connection and store it in FTP_SERVER.data_reply
   *        - check whether data connection is closed
   */
  procedure read_data(
    p_command in varchar2,
    p_expected_code in code_tab default null)
  as
  begin
    pit.enter_detailed('read_data', c_pkg);
    get_data_connection;
    do_command(p_command, p_expected_code);
    read_reply(p_command);
    get_response(p_command, code_tab(226));
    pit.leave_detailed;
  exception
    when others then
      pit.leave_detailed;
      raise;
  end read_data;
  
  
  /* Methode zur Einstellung des Uebertragungserhaltens (C_TYPE_BINARY|C_TYPE_ASCII)
   * %param p_connection Verbindung zum FTP-Server
   * %param p_transfer_mode Typ der Datenuebertragung
   * %usage Wird intern verwendet, um CLOB als C_TYPE_ASCII und BLOB als
   *        C_TYPE_BINARY zu uebertragen.
   */
  procedure set_transfer_type(
    p_transfer_mode in varchar2) 
  as
  begin
    pit.enter_optional('binary', c_pkg);
    if p_transfer_mode = c_type_binary then
      do_command(c_ftp_transfer_binary, code_tab(200));
      g_binary := true;
      g_open_mode := c_write_byte;
    else
      do_command(c_ftp_transfer_ascii, code_tab(200));
      g_binary := false;
      g_open_mode := c_write_text;
    end if;
    pit.leave_optional;
  exception
    when others then
      pit.leave_optional;
      raise;
  end set_transfer_type;
  
  
  /* Accessor to internal server list that stores registered servers
   * %param p_ftp_server Nickname of registered server
   * %return server record for nickname, if present
   * %usage Called internally to retrieve logon information and access to generic
   *        server attributes. Throws an error if nickname is unknown.
   */
  procedure get_ftp_server(
    p_ftp_server in varchar2)
  as
  begin
    pit.enter_optional('get_ftp_server', c_pkg);
    if g_server_list.exists(upper(p_ftp_server)) then
      g_server := g_server_list(upper(p_ftp_server));
    else
      pit.error(msg.FTP_INVALID_SERVER, msg_args(p_ftp_server));
    end if;
    pit.leave_optional;
  exception
    when others then
      pit.leave_optional;
      raise;
  end get_ftp_server;
  
  
  /* initialization method to read predefined ftp server settings
   * %usage Called internally upon package initialization of the package
   */
  procedure initialize
  as
    cursor registered_servers is
      select upper(ftp_id) ftp_id, ftp_host_name, ftp_port, ftp_user_name, ftp_password
        from ftp_server;
  begin
    pit.enter_optional('initialize', c_pkg);
    for srv in registered_servers loop
      register_ftp_server(
        p_ftp_server => srv.ftp_id,
        p_host_name => srv.ftp_host_name,
        p_port => srv.ftp_port,
        p_user_name => srv.ftp_user_name,
        p_password => srv.ftp_password,
        p_permanent => false);
    end loop;
    pit.leave_optional;
  exception
    when others then
      pit.leave_optional;
      raise;
  end initialize;
  
  
  /* LOGIN procedure (internal)
   * Logs FTP server gathered from FTP_SERVER_LIST in
   */
  procedure login
  as
  begin
    pit.enter_mandatory('login', c_pkg);
    g_server.control_reply := ftp_reply_tab();
    g_server.data_reply := ftp_reply_tab();
  
    g_server.control_connection := 
      utl_tcp.open_connection(
        remote_host => g_server.host_name,
        remote_port => g_server.port,
        tx_timeout => 30);
    get_response('login', code_tab(220));
    do_command(c_ftp_user_name || g_server.user_name, code_tab(331));
    do_command(c_ftp_password || g_server.password, code_tab(230));
    pit.leave_mandatory;
  exception
    when others then
      pit.leave_mandatory;
      raise;
  end login;
  
 
  /* Helper to automatically create a session if no explicit session exists
   * %param p_ftp_server Nickname of the FTP server to connect to
   * %usage Is called by any command accessing the server. It pings the FTP server
   *        to see whether it's available and creates a session, if not.
   *        In this case, the session is marked as AUTO and automatically
   *        closed at the end of the command.
   */
  procedure auto_login(
    p_ftp_server in varchar2)
  as
  begin
    pit.enter_optional('auto_login', c_pkg);
    if g_server.host_name is null then
      get_ftp_server(p_ftp_server);
      login;
      g_server.auto_session := true;
    end if;
    pit.leave_optional;
  exception
    when others then
      pit.leave_optional;
      raise;
  end auto_login;
  
  
  /* Closes the session if it is marked as AUTO
   * %param p_ftp_server Nickname of the registered server
   * %usage Called at the end of a command to check whether an automatically
   *        created session needs to be destroyed
   */
  procedure auto_logout
  as
  begin
    pit.enter_optional('auto_logout', c_pkg);
    if g_server.auto_session then
      logout;
    else
      dbms_output.put_line('No auto session detected.');
    end if;
    pit.leave_optional;
  exception
    when others then
      pit.leave_optional;
      raise;
  end auto_logout;
  
  
  /* INTERFACE */
  procedure register_ftp_server(
    p_ftp_server in varchar2,
    p_host_name in varchar2,
    p_port in varchar2 default '21',
    p_user_name in varchar2 default 'anonymous',
    p_password in varchar2 default 'foo',
    p_permanent in boolean default true)
  as
    l_ftp_server ftp_server_rec;
  begin
    pit.enter_mandatory('register_ftp_server', c_pkg);
    pit.assert(length(p_ftp_server) <= 30);
    pit.assert_not_null(p_host_name);
    pit.assert_not_null(p_port);
    
    -- register local
    l_ftp_server.host_name := p_host_name;
    l_ftp_server.port := p_port;
    l_ftp_server.user_name := p_user_name;
    l_ftp_server.password := p_password;
    g_server_list(upper(p_ftp_server)) := l_ftp_server;
    
    -- register permanent
    if p_permanent then
      merge into ftp_server ftp
      using (select upper(p_ftp_server) ftp_id,
                    p_host_name ftp_host_name,
                    p_port ftp_port,
                    p_user_name ftp_user_name,
                    p_password ftp_password
               from dual) v
         on (upper(ftp.ftp_id) = v.ftp_id)
       when matched then update set
            ftp_host_name = v.ftp_host_name,
            ftp_port = v.ftp_port,
            ftp_user_name = v.ftp_user_name,
            ftp_password = v.ftp_password
       when not matched then insert (ftp_id, ftp_host_name, ftp_port, ftp_user_name, ftp_password)
            values (v.ftp_id, v.ftp_host_name, v.ftp_port, v.ftp_user_name, v.ftp_password);
    end if;
    pit.leave_mandatory;
  exception
    when others then
      pit.leave_mandatory;
      raise;
  end register_ftp_server;
  
  
  procedure unregister_ftp_server(
    p_ftp_server in varchar2)
  as
  begin
    pit.enter_mandatory('unregister_ftp_server', c_pkg);
    if g_server_list.exists(upper(p_ftp_server)) then
      g_server_list.delete(upper(p_ftp_server));
      delete from ftp_server
       where ftp_id = p_ftp_server;
      commit;
    end if;
    pit.leave_mandatory;
  exception
    when others then
      pit.leave_mandatory;
      raise;
  end unregister_ftp_server;
  
  
  /* Wrapper for login that fetches the respective server from server list and logs in */
  procedure login(
    p_ftp_server in varchar2)
  as
  begin
    pit.enter_mandatory('login', c_pkg);
    get_ftp_server(p_ftp_server);
    login;
    pit.leave_mandatory;
  exception
    when others then
      pit.leave_mandatory;
      raise;
  end login;
  

  procedure logout
  as
  begin
    pit.enter_mandatory('logout', c_pkg);
    do_command(c_ftp_quit, code_tab(221));
    utl_tcp.close_connection(g_server.control_connection);
    g_server := null;
    pit.leave_mandatory;
  exception
    when others then
      pit.leave_mandatory;
      raise;
  end logout;
  
  
  /* COMMANDS */
  procedure get(
    p_ftp_server in varchar2,
    p_from_file in varchar2,
    p_to_directory in varchar2,
    p_to_file in varchar2,
    p_transfer_type in varchar2 default c_type_binary) 
  as
    l_out_file utl_file.file_type;
    l_amount pls_integer;
    l_buffer chunk_type;
    l_raw_buffer raw_chunk_type;
  begin
    pit.enter_mandatory('get', c_pkg);
    auto_login(p_ftp_server);
    
    set_transfer_type(p_transfer_type);
    do_command(c_ftp_retrieve || p_from_file);
    
    l_out_file := utl_file.fopen(p_to_directory, p_to_file, g_open_mode, c_chunk_size);
  
    begin
      loop
        if g_binary then
          l_amount := utl_tcp.read_raw(g_server.data_connection, l_raw_buffer, c_chunk_size);
          utl_file.put_raw(l_out_file, l_raw_buffer, true);
        else
          l_amount := utl_tcp.read_text(g_server.data_connection, l_buffer, c_chunk_size);
          utl_file.put(l_out_file, l_buffer);
        end if;
        utl_file.fflush(l_out_file);
      end loop;
    exception
      when utl_tcp.end_of_input then
        pit.info(msg.FTP_FILE_RECEIVED);
      when others then
        pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
    end;
    utl_file.fclose(l_out_file);
    read_reply('get');
    utl_tcp.close_connection(g_server.data_connection);
    
    auto_logout;
    pit.leave_mandatory;
  exception
    when others then
      if utl_file.is_open(l_out_file) then
        utl_file.fclose(l_out_file);
      end if;
      auto_logout;
      pit.stop(msg.SQL_ERROR, msg_args(sqlerrm));
  end get;
  
  
  procedure get(
    p_ftp_server in varchar2,
    p_from_file in varchar2,
    p_data out nocopy clob,
    p_transfer_type in varchar2 default c_type_binary)
  as
    l_amount pls_integer;
    l_buffer chunk_type;
  begin
    pit.enter_mandatory('get', c_pkg);
    auto_login(p_ftp_server);
    dbms_lob.createtemporary(p_data, true, dbms_lob.call);
    set_transfer_type(p_transfer_type);
    
    -- Request file from FTP server
    do_command(c_ftp_retrieve || p_from_file);
    
    -- copy file to local CLOB
    begin
      loop
        l_amount := utl_tcp.read_text(g_server.data_connection, l_buffer, c_chunk_size);
        dbms_lob.writeappend(p_data, l_amount, l_buffer);
      end loop;
    exception
      when utl_tcp.end_of_input then
      null;
        pit.info(msg.FTP_FILE_RECEIVED);
      when others then
        pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
    end;
    read_reply('get');
    utl_tcp.close_connection(g_server.data_connection);
  
    auto_logout;
    pit.leave_mandatory;
  exception
    when others then
      auto_logout;
      pit.stop(msg.SQL_ERROR, msg_args(sqlerrm));
  end get;
    
    
  procedure get(
    p_ftp_server in varchar2,
    p_from_file in varchar2,
    p_data out nocopy blob)
  as
    l_amount pls_integer;
    l_buffer raw_chunk_type;
  begin
    pit.enter_mandatory('get', c_pkg);
    auto_login(p_ftp_server);
    dbms_lob.createtemporary(p_data, true, dbms_lob.call);
    set_transfer_type(c_type_binary);
    
    -- Request file from FTP server
    do_command(c_ftp_retrieve || p_from_file);
  
    -- copy file to local BLOB
    begin
      loop
        l_amount := utl_tcp.read_raw(g_server.data_connection, l_buffer, c_chunk_size);
        dbms_lob.writeappend(p_data, l_amount, l_buffer);
      end loop;
    exception
      when utl_tcp.end_of_input then
        null;
        pit.info(msg.FTP_FILE_RECEIVED);
      when others then
        pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
    end;
    
    -- Read confirmation and clean up
    read_reply('get');
    utl_tcp.close_connection(g_server.data_connection);
  
    auto_logout;
    pit.leave_mandatory;
  exception
    when others then
      auto_logout;
      pit.stop(msg.SQL_ERROR, msg_args(sqlerrm));
  end get;
 
 
  procedure put(
    p_ftp_server in varchar2,
    p_from_directory in varchar2,
    p_from_file in varchar2,
    p_to_file in varchar2,
    p_transfer_type in varchar2 default c_type_binary) 
  as
    l_bfile bfile;
    l_result pls_integer;
    l_amount pls_integer := c_chunk_size;
    l_string_buffer chunk_type;
    l_raw_buffer raw_chunk_type;
    l_length number;
    l_idx number := 1;
  begin
    pit.enter_mandatory('put', c_pkg);
    auto_login(p_ftp_server);
    do_command(c_ftp_store || p_to_file);
  
    -- open local file
    l_bfile := bfilename(p_from_directory, p_from_file);
    dbms_lob.fileopen(l_bfile, dbms_lob.file_readonly);
    l_length := dbms_lob.getlength(l_bfile);
  
    -- copy local file to FTP server
    while l_idx <= l_length loop
      if g_binary then
        dbms_lob.read(l_bfile, l_amount, l_idx, l_raw_buffer);
        l_result := utl_tcp.write_raw(g_server.data_connection, l_raw_buffer, l_amount);
      else
        dbms_lob.read(l_bfile, l_amount, l_idx, l_string_buffer);
        l_result := utl_tcp.write_text(g_server.data_connection, l_string_buffer, l_amount);
      end if;
      l_idx := l_idx + l_amount;
    end loop;
    pit.info(msg.FTP_FILE_SENT);
  
    dbms_lob.fileclose(l_bfile);
    utl_tcp.close_connection(g_server.data_connection);
  
    auto_logout;
    pit.leave_mandatory;
  exception
    when others then
      if dbms_lob.fileisopen(l_bfile) = 1 then
        dbms_lob.fileclose(l_bfile);
      end if;
      auto_logout;
      pit.stop(msg.SQL_ERROR, msg_args(sqlerrm));
  end put;
  
    
  procedure put(
    p_ftp_server in varchar2,
    p_to_file in varchar2,
    p_clob in clob default null,
    p_blob in blob default null,
    p_transfer_type in varchar2 default c_type_ascii)
  as
    l_result pls_integer;
    l_string_buffer chunk_type;
    l_raw_buffer raw_chunk_type;
    l_amount binary_integer := c_chunk_size;
    l_idx integer := 1;
    l_length integer;
  begin
    pit.enter_mandatory('put', c_pkg);
    auto_login(p_ftp_server);
    case   
    when p_blob is not null then
      set_transfer_type(c_type_binary);
    when p_clob is not null then
      set_transfer_type(p_transfer_type);
    else
      raise msg.FTP_NO_PAYLOAD_ERR;
    end case;
    
    do_command(c_ftp_store || p_to_file);
  
    -- write stream to the FTP server
    l_length := coalesce(dbms_lob.getlength(p_blob), dbms_lob.getlength(p_clob));
    while l_idx <= l_length loop
      if g_binary then
        dbms_lob.read(p_blob, l_amount, l_idx, l_raw_buffer);
        l_result := utl_tcp.write_raw(g_server.data_connection, l_raw_buffer, l_amount);
      else
        dbms_lob.read(p_clob, l_amount, l_idx, l_string_buffer);
        l_result := utl_tcp.write_text(g_server.data_connection, l_string_buffer, l_amount);
      end if;    
      utl_tcp.flush(g_server.data_connection);
      l_idx := l_idx + l_amount;
    end loop;
    pit.info(msg.FTP_FILE_SENT);
  
    auto_logout;
    pit.leave_mandatory;
  exception
    when msg.FTP_NO_PAYLOAD_ERR then
      null;
      pit.stop(msg.FTP_NO_PAYLOAD);
    when others then
      pit.stop(msg.SQL_ERROR);
  end put;
 
 
  function get_server_status
    return char_table pipelined
  as
    l_result number;
  begin
    pit.enter_mandatory('get_server_status', c_pkg);
    
    -- get server and execute command locally
    -- Do not call DO_COMMAND here, as C_FTP_STATUS retrieves information over control connection
    -- rather than data connection. 
    l_result := UTL_TCP.write_text(g_server.control_connection, c_ftp_status || utl_tcp.crlf, length(c_ftp_status || utl_tcp.crlf));
    
    -- read control content
    while utl_tcp.available(g_server.control_connection, 0.5) > 0 loop
      begin
        pipe row (trim(utl_tcp.get_line(g_server.control_connection, true)));
      exception
        when utl_tcp.end_of_input then
          exit;
      end;
    end loop;
    
    pit.leave_mandatory;
    return;
  end get_server_status;
    

  function get_control_log
    return ftp_reply_tab pipelined
  as
  begin
    pit.enter_mandatory('get_control_log', c_pkg);
    for i in g_server.control_reply.first .. g_server.control_reply.last loop
      pipe row (g_server.control_reply(i));
    end loop;
    pit.leave_mandatory;
    return;
  end get_control_log;
  
    
  function get_help(
    p_ftp_server in varchar2,
    p_command in varchar2 default null)
    return char_table pipelined
  as
    l_command varchar2(100) := trim(c_ftp_help || p_command);
    l_result number;
  begin
    pit.enter_mandatory('get_help', c_pkg);
    auto_login(p_ftp_server);
    l_result := UTL_TCP.write_text(g_server.control_connection, l_command || utl_tcp.crlf, length(l_command || utl_tcp.crlf));
    while utl_tcp.available(g_server.control_connection, 0.5) > 0 loop
      begin
        pipe row (trim(utl_tcp.get_line(g_server.control_connection, true)));
      exception
        when utl_tcp.end_of_input then
          exit;
      end;
    end loop;
    auto_logout;
    pit.leave_mandatory;
    return;
  exception
    when others then
      auto_logout;
      pit.stop(msg.SQL_ERROR, msg_args(sqlerrm));
  end get_help;


  function list_directory(
    p_ftp_server in varchar2,
    p_directory in varchar2 default null)
    return ftp_list_tab pipelined
  as
    l_data_reply ftp_reply_tab;
  begin
    pit.enter_mandatory('list_directory', c_pkg);
    
    auto_login(p_ftp_server);

    set_transfer_type(c_type_binary);
    read_data(c_ftp_list || p_directory, code_tab(150));
    l_data_reply := g_server.data_reply;
    if l_data_reply is not null then
      for i in l_data_reply.first .. l_data_reply.last loop
        pipe row (convert_directory_list(l_data_reply(i).message));
      end loop;
    end if;
    
    auto_logout;
    pit.leave_mandatory;
    return;
  end list_directory;
  
  
  procedure create_directory(
    p_ftp_server in varchar2,
    p_directory in varchar2) 
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


  procedure remove_directory(
    p_ftp_server in varchar2,
    p_directory in varchar2)
  as
  begin
    pit.enter_mandatory('remove_directory', c_pkg);
    auto_login(p_ftp_server);
    do_command(c_ftp_remove_directory || p_directory, code_tab(250));
    auto_logout;
    pit.leave_mandatory;
  exception
    when others then
      auto_logout;
      pit.stop(msg.SQL_ERROR, msg_args(sqlerrm));
  end remove_directory;


  procedure rename_file(
    p_ftp_server in varchar2,
    p_from in varchar2,
    p_to in varchar2) 
  as
  begin
    pit.enter_mandatory('rename_file', c_pkg);
    auto_login(p_ftp_server);
    do_command(c_ftp_rename_from || p_from, code_tab(350));
    do_command(c_ftp_rename_to || p_to, code_tab(250));
    auto_logout;
    pit.leave_mandatory;
  exception
    when others then
      auto_logout;
      pit.stop(msg.SQL_ERROR, msg_args(sqlerrm));
  end rename_file;


  procedure delete_file(
    p_ftp_server in varchar2,
    p_file in varchar2)
  as
  begin
    pit.enter_mandatory('delete_file', c_pkg);
    auto_login(p_ftp_server);
    do_command(c_ftp_delete || p_file, code_tab(250));
    auto_logout;
    pit.leave_mandatory;
  exception
    when others then
      auto_logout;
      pit.stop(msg.SQL_ERROR, msg_args(sqlerrm));
  end delete_file;

begin
  initialize;
end utl_ftp;
/