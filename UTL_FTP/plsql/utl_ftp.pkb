create or replace package body utl_ftp
as
  -- --------------------------------------------------------------------------
  -- Name         : UTL_FTP
  -- Author       : Juergen Sieben, based on the work of Tim Hall
  -- Description  : Simple FTP-API for in database use
  -- Requirements : UTL_TCP
  -- --------------------------------------------------------------------------

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

  -- FTP error return code groups
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

  -- global variable for active server session.
  -- Active session may not be taken from the PL/SQL-list in each method,
  -- as this creates a deep copy instead of a reference
  g_server ftp_server_rec;
  g_timeout number;

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
    pit.enter_optional(
      p_params => msg_params(msg_param('p_ftp_server', p_ftp_server)));
    if g_server_list.exists(upper(p_ftp_server)) then
      g_server := g_server_list(upper(p_ftp_server));
    else
      pit.error(msg.FTP_INVALID_SERVER, msg_args(p_ftp_server));
    end if;
    pit.leave_optional;
  exception
    when others then
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end get_ftp_server;


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

    c_date_format constant varchar2(20) := 'YYYYMMDDHH24MISS';
  begin
    pit.enter_detailed(
      p_params => msg_params(msg_param('p_entry', p_entry)));
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
        when 'MODIFY' then l_ftp_list.item_modify_date := to_date(l_value, c_date_format);
        when 'CREATE' then l_ftp_list.item_creation_date := to_date(l_value, c_date_format);
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
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end convert_directory_list;


  /* Method to check response of a command
   * %param p_expected_code List of expected return codes
   * %param p_reply Single reply of type FTP_REPLY_T with attributes CODE and MESSAGE
   * %usage Checks the reply received for:
   *        <ul><li>Transient and permanent errors</li>
   *        <li>Outcome code against the list of expected codes</li>
   *        <li>Unexptected return codes</li></ul>
   */
  procedure check_response(
    p_expected_code in code_tab,
    p_reply in ftp_reply_t)
  as
    l_ok boolean := false;
  begin
    pit.enter_detailed;

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
    when msg.FTP_TRANSIENT_ERROR_ERR then
      pit.sql_exception(msg.FTP_TRANSIENT_ERROR, msg_args(p_reply.message));
    when msg.FTP_PERMANENT_ERROR_ERR then
      pit.sql_exception(msg.FTP_PERMANENT_ERROR, msg_args(p_reply.message));
    when others then
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end check_response;


  /* Method to read output of the control connection
   * %param p_expected_code List of expected codes (will be forwarded to CHECK_RESPONSE)
   * %param p_multi_response Flag that indicates whether a command will possibly
   *        return more than one return message, such as LOGIN
   * %usage Copies all output of control connection into CONTROL_REPLY attribute.
   */
  procedure get_response(
    p_expected_code in code_tab,
    p_multi_response in boolean)
  as
    l_response varchar2(32767);
    l_reply ftp_reply_t;
  begin
    pit.enter_detailed;
    loop
      begin
        if utl_tcp.available(g_server.control_connection, g_timeout) > 0 then
          l_response := utl_tcp.get_line(g_server.control_connection, true);
          -- render response and push to list
          if regexp_like(l_response, '^[0-9]{3}') then
            l_reply := ftp_reply_t(to_number(substr(l_response, 1, 3)), substr(l_response, 5));
            push_list(g_server.control_reply, l_reply);
            check_response(p_expected_code, l_reply);
          end if;
          if not p_multi_response then
            exit;
          end if;
        else
          -- no more output, leave loop
          exit;
        end if;
      exception
        when utl_tcp.end_of_input then
          exit;
      end;
    end loop;

    pit.leave_detailed;
  exception
    when others then
      pit.sql_exception(msg.sql_error, msg_args(sqlerrm));
  end get_response;


  /* Method to read output of the data connection
   * %param p_command Information about the command for which result shall be read
   * %usage Copies all output of control connection into DATA_REPLY attribute.
   *        As more than one response is possible, it is necessary to pool until
   *        either UTL_TCP.END_OF_INPUT is raised or the method times out.
   *        To avoid frequent unnecessary time out events, a warning is raised to
   *        give an indication to the user that this command may not require
   *        this method to process its output.
   */
  procedure read_reply(
    p_command in varchar2)
  as
    l_reply ftp_reply_t;
  begin
    pit.enter_detailed(
      p_params => msg_params(msg_param('p_command', p_command)));
    -- designed as a basic loop to allow for reporting of unnecessary calls
    loop
      begin
        if utl_tcp.available(g_server.data_connection, g_timeout) > 0 then
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
    pit.leave_detailed;
  exception
    when others then
      pit.leave_detailed;
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end read_reply;


  /* Method to send a ftp command
   * %param p_command FTP command to execute
   * %param p_expected_code Optional list of expected results. Used for cross check
   * %param p_multi_response Flag to indicate whether a command may expect multiple
   *        result messages
   * %usage Called internally to execute a FTP comman at the actually selected FTP server
   */
  procedure do_command(
    p_command in varchar2,
    p_expected_code in code_tab default null,
    p_multi_response boolean default false)
  as
    l_result pls_integer;
  begin
    pit.enter_detailed(
      p_params => msg_params(msg_param('p_command', p_command)));

    l_result := UTL_TCP.write_text(
                  g_server.control_connection,
                  p_command || utl_tcp.crlf,
                  length(p_command || utl_tcp.crlf));
    get_response(p_expected_code, p_multi_response);

    pit.leave_detailed;
  exception
    when others then
      pit.leave_detailed;
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end do_command;


  /* Method to control the transfer mode (C_TYPE_BINARY|C_TYPE_ASCII)
   * %param p_transfer_mode Type requested
   * %usage Is used to transfer CLOB or file content either as
   *        C_TYPE_ASCII or as C_TYPE_BINARY
   */
  procedure set_transfer_type(
    p_transfer_mode in varchar2)
  as
  begin
    pit.enter_optional(
      p_params => msg_params(msg_param('p_transfer_mode', p_transfer_mode)));

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
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end set_transfer_type;


  /* Method to get a data connection to the FTP server in passive mode (PASV)
   * %param p_transfer_type mode in which the data transfer should be made
   *        (C_TYPE_ASCII | C_TYPE_BINARY)
   * %usage Sets data connection for the actually selected FTP server
   */
  procedure get_data_connection(
    p_transfer_type in varchar2)
  as
    l_message varchar2(25);
    l_port number(10);
  begin
    pit.enter_detailed(
      p_params => msg_params(msg_param('p_transfer_type', p_transfer_type)));

    set_transfer_type(p_transfer_type);
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
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end get_data_connection;


  /* Method to close a data connection after data submission */
  procedure close_data_connection
  as
  begin
    pit.enter_detailed;
    
    utl_tcp.close_connection(g_server.data_connection);
    get_response(code_tab(226), false);
    
    pit.leave_detailed;
  exception
    when others then
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end close_data_connection;


  /* Wrapper method to issue a command and read data from the data connection
   * %param p_transfer_type mode in which the data transfer should be made
   *        (C_TYPE_ASCII | C_TYPE_BINARY) routed through to GET_DATA_CONNECTION
   * %param p_command Command to execute
   * %param p_expected_code Optional list of result codes expected on the control connection
   * %usage Called internally to execute P_COMMAND and read data from DATA_CONNECTION.
   *        Flow:<ul>
   *        <li>Open data connection</li>
   *        <li>Issue command over control connection and check return code</li>
   *        <li>read data from data connection and store it in FTP_SERVER.data_reply</li>
   *        <li>check whether data connection is closed</li></ul>
   */
  procedure read_data(
    p_transfer_type in varchar2,
    p_command in varchar2,
    p_expected_code in code_tab default null)
  as
  begin
    pit.enter_detailed(
      p_params => msg_params(
                    msg_param('p_transfer_type', p_transfer_type),
                    msg_param('p_command', p_command)));

    get_data_connection(p_transfer_type);
    do_command(p_command, p_expected_code);
    read_reply(p_command);
    get_response(code_tab(226), true);

    pit.leave_detailed;
  exception
    when others then
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end read_data;


  /* initialization method to read predefined ftp server settings
   * %usage Called internally upon package initialization of the package
   */
  procedure initialize
  as
    cursor registered_servers is
      select upper(ftp_id) ftp_id, ftp_host_name, ftp_port, ftp_user_name, ftp_password
        from ftp_server;
  begin
    pit.enter_optional;

    -- adjust timeout duration
    g_timeout := 0.5;

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
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end initialize;


  /* LOGIN procedure (internal)
   * Logs into G_SERVER gathered from FTP_SERVER_LIST
   */
  procedure login
  as
  begin
    pit.enter_mandatory;

    -- Initialize REPLY collections
    g_server.control_reply := ftp_reply_tab();
    g_server.data_reply := ftp_reply_tab();

    -- contact server
    g_server.control_connection :=
      utl_tcp.open_connection(
        remote_host => g_server.host_name,
        remote_port => g_server.port,
        tx_timeout => 30);
    get_response(code_tab(220), true);

    -- Pass login credentials
    do_command(c_ftp_user_name || g_server.user_name, code_tab(331));
    do_command(c_ftp_password || g_server.password, code_tab(230));

    pit.leave_mandatory;
  exception
    when others then
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
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
    pit.enter_optional(
      p_params => msg_params(msg_param('p_ftp_server', p_ftp_server)));

    if g_server.host_name is null then
      if p_ftp_server is not null then
        get_ftp_server(p_ftp_server);
        login;
        g_server.auto_session := true;
      else
        pit.error(msg.FTP_INVALID_SERVER, msg_args(''));
      end if;
    end if;

    pit.leave_optional;
  exception
    when others then
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end auto_login;


  /* Closes the session if it is marked as AUTO
   * %usage Called at the end of a command to check whether an automatically
   *        created session needs to be destroyed
   */
  procedure auto_logout
  as
  begin
    pit.enter_optional;

    if g_server.auto_session then
      logout;
    end if;

    pit.leave_optional;
  exception
    when others then
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
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
    pit.enter_mandatory(
      p_params => msg_params(
                    msg_param('p_ftp_server', p_ftp_server),
                    msg_param('p_host_name', p_host_name),
                    msg_param('p_port', p_port),
                    msg_param('p_user_name', p_user_name),
                    msg_param('p_password', lpad('*', length(p_password), '*')),
                    msg_param('p_permanent', case when p_permanent then 'true' else 'false' end)));
    
    pit.assert(length(p_ftp_server) <= 30, msg.FTP_INVALID_SERVER_NAME);
    pit.assert_not_null(p_host_name);
    pit.assert_not_null(p_port);

    -- register local
    l_ftp_server.host_name := upper(p_host_name);
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
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end register_ftp_server;


  procedure unregister_ftp_server(
    p_ftp_server in varchar2)
  as
  begin
    pit.enter_mandatory(
      p_params => msg_params(msg_param('p_ftp_server', p_ftp_server)));

    if g_server_list.exists(upper(p_ftp_server)) then
      g_server_list.delete(upper(p_ftp_server));
      delete from ftp_server
       where upper(ftp_id) = upper(p_ftp_server);
      commit;
    end if;

    pit.leave_mandatory;
  exception
    when others then
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end unregister_ftp_server;


  procedure set_timeout(
    p_duration in number)
  as
  begin
    pit.enter_mandatory(
      p_params => msg_params(msg_param('p_duration', to_char(p_duration))));
      
    pit.assert(p_duration between 0.1 and 30, msg.FTP_MAX_TIMEOUT);
    g_timeout := p_duration;
    
    pit.leave_mandatory;
  end set_timeout;


  procedure login(
    p_ftp_server in varchar2)
  as
  begin
    pit.enter_mandatory(
      p_params => msg_params(msg_param('p_ftp_server', p_ftp_server)));

    get_ftp_server(p_ftp_server);
    login;

    pit.leave_mandatory;
  exception
    when others then
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end login;


  procedure logout
  as
  begin
    pit.enter_mandatory;

    do_command(c_ftp_quit, code_tab(221));
    utl_tcp.close_connection(g_server.control_connection);
    g_server := null;

    pit.leave_mandatory;
  exception
    when others then
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end logout;


  /* COMMANDS */
  procedure get(
    p_from_file in varchar2,
    p_to_directory in varchar2,
    p_to_file in varchar2,
    p_ftp_server in varchar2 default null,
    p_transfer_type in varchar2 default c_type_binary)
  as
    l_out_file utl_file.file_type;
    l_amount pls_integer;
    l_buffer chunk_type;
    l_raw_buffer raw_chunk_type;
  begin
    pit.enter_mandatory(
      p_params => msg_params(
                    msg_param('p_from_file', p_from_file),
                    msg_param('p_to_directory', p_to_directory),
                    msg_param('p_to_file', p_to_file),
                    msg_param('p_ftp_server', p_ftp_server),
                    msg_param('p_transfer_type', p_transfer_type)));
                    
    auto_login(p_ftp_server);
    get_data_connection(p_transfer_type);

    do_command(c_ftp_retrieve || p_from_file, code_tab(227, 150));

    l_out_file := utl_file.fopen(p_to_directory, p_to_file, g_open_mode, c_chunk_size);
    -- write content from FTP server to local file
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
    close_data_connection;

    auto_logout;
    
    pit.leave_mandatory;
  exception
    when others then
      if utl_file.is_open(l_out_file) then
        utl_file.fclose(l_out_file);
      end if;
      logout;
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end get;


  procedure get(
    p_from_file in varchar2,
    p_data out nocopy clob,
    p_ftp_server in varchar2 default null,
    p_transfer_type in varchar2 default c_type_binary)
  as
    l_amount pls_integer;
    l_buffer chunk_type;
  begin
    pit.enter_mandatory(
      p_params => msg_params(
                    msg_param('p_from_file', p_from_file),
                    msg_param('p_ftp_server', p_ftp_server),
                    msg_param('p_transfer_type', p_transfer_type)));
                    
    auto_login(p_ftp_server);
    get_data_connection(p_transfer_type);
    dbms_lob.createtemporary(p_data, true, dbms_lob.call);

    -- Request file from FTP server
    do_command(c_ftp_retrieve || p_from_file, code_tab(150));

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

    close_data_connection;
    auto_logout;
    
    pit.leave_mandatory(
      p_params => msg_params(
                    msg_param('p_data', dbms_lob.substr(p_data, 4000, 1))));
  exception
    when others then
      logout;
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end get;


  procedure get(
    p_from_file in varchar2,
    p_data out nocopy blob,
    p_ftp_server in varchar2 default null)
  as
    l_amount pls_integer;
    l_buffer raw_chunk_type;
  begin
    pit.enter_mandatory(
      p_params => msg_params(
                    msg_param('p_from_file', p_from_file),
                    msg_param('p_ftp_server', p_ftp_server)));
                    
    auto_login(p_ftp_server);
    get_data_connection(c_type_binary);
    dbms_lob.createtemporary(p_data, true, dbms_lob.call);

    -- Request file from FTP server
    do_command(c_ftp_retrieve || p_from_file, code_tab(150));

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
    close_data_connection;
    auto_logout;
    pit.leave_mandatory(
      p_params => msg_params(
                    msg_param('Bytes read', to_char(dbms_lob.getlength(p_data)))));
  exception
    when others then
      logout;
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end get;


  procedure put(
    p_from_directory in varchar2,
    p_from_file in varchar2,
    p_to_file in varchar2,
    p_ftp_server in varchar2 default null,
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
    pit.enter_mandatory(
      p_params => msg_params(
                    msg_param('p_from_directory', p_from_directory),
                    msg_param('p_from_file', p_from_file),
                    msg_param('p_to_file', p_to_file),
                    msg_param('p_ftp_server', p_ftp_server),
                    msg_param('p_transfer_type', p_transfer_type)));
                    
    auto_login(p_ftp_server);
    get_data_connection(p_transfer_type);

    do_command(c_ftp_store || p_to_file, code_tab(150));

    -- open local file
    l_bfile := bfilename(p_from_directory, p_from_file);
    dbms_lob.fileopen(l_bfile, dbms_lob.file_readonly);
    l_length := dbms_lob.getlength(l_bfile);
    pit.verbose(msg.FTP_FILE_READ, msg_args(p_from_directory, p_from_file, to_char(l_length)));

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

    -- Close file and cleanup
    dbms_lob.fileclose(l_bfile);
    close_data_connection;
    auto_logout;
    
    pit.leave_mandatory;
  exception
    when others then
      if l_bfile is not null and dbms_lob.fileisopen(l_bfile) = 1 then
        dbms_lob.fileclose(l_bfile);
      end if;
      logout;
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end put;


  procedure put(
    p_to_file in varchar2,
    p_clob in clob default null,
    p_blob in blob default null,
    p_ftp_server in varchar2 default null,
    p_transfer_type in varchar2 default c_type_ascii)
  as
    l_result pls_integer;
    l_string_buffer chunk_type;
    l_raw_buffer raw_chunk_type;
    l_amount binary_integer := c_chunk_size;
    l_idx integer := 1;
    l_length integer;
    l_transfer_type char(1 byte);
  begin
    pit.enter_mandatory(
      p_params => msg_params(
                    msg_param('p_to_file', p_to_file),
                    msg_param('p_clob', case when p_clob is not null then 'true' else 'false' end),
                    msg_param('p_blob', case when p_blob is not null then 'true' else 'false' end),
                    msg_param('p_ftp_server', p_ftp_server),
                    msg_param('p_transfer_type', p_transfer_type)));
                    
    auto_login(p_ftp_server);

    -- Check type of data stream and set transfer mode
    case
    when p_blob is not null then
      l_transfer_type := c_type_binary;
    when p_clob is not null then
      l_transfer_type := p_transfer_type;
    else
      raise msg.FTP_NO_PAYLOAD_ERR;
    end case;

    get_data_connection(l_transfer_type);
    do_command(c_ftp_store || p_to_file, code_tab(150));

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

    -- clean up
    close_data_connection;
    auto_logout;
    
    pit.leave_mandatory;
  exception
    when msg.FTP_NO_PAYLOAD_ERR then
      logout;
      pit.sql_exception(msg.FTP_NO_PAYLOAD);
    when others then
      logout;
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end put;


  function get_server_status(
    p_ftp_server in varchar2 default null)
    return char_table pipelined
  as
    l_result number;
  begin
    pit.enter_mandatory(
      p_params => msg_params(
                    msg_param('p_ftp_server', p_ftp_server)));
    auto_login(p_ftp_server);

    -- get server and execute command locally
    -- Do not call READ_DATA or DO_COMMAND here, as C_FTP_STATUS retrieves
    -- information over control connection rather than data connection.
    l_result := UTL_TCP.write_text(g_server.control_connection, c_ftp_status || utl_tcp.crlf, length(c_ftp_status || utl_tcp.crlf));

    -- read control content and pipe it
    while utl_tcp.available(g_server.control_connection, g_timeout) > 0 loop
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
      logout;
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end get_server_status;


  function get_control_log
    return ftp_reply_tab pipelined
  as
  begin
    pit.enter_mandatory;

    -- No AUTO_LOGIN here as a control log is only available in an explicit session
    for i in g_server.control_reply.first .. g_server.control_reply.last loop
      pipe row (g_server.control_reply(i));
    end loop;

    pit.leave_mandatory;
    return;
  end get_control_log;
  
  
  function get_control_log_text
    return clob
  as
    cursor control_log_cur is
      select code || ': ' || message || c_cr msg
        from table(
              utl_ftp.get_control_log);
    l_result clob;
  begin
    pit.enter_mandatory;
    
    dbms_lob.createtemporary(l_result, false, dbms_lob.call);
    for ctl in control_log_cur loop
      dbms_lob.append(ctl.msg, l_result);
    end loop;
    
    pit.leave_mandatory;
    return l_result;
  end get_control_log_text;


  function get_help(
    p_command in varchar2 default null,
    p_ftp_server in varchar2 default null)
    return char_table pipelined
  as
    l_command varchar2(100) := trim(c_ftp_help || p_command);
    l_result number;
  begin
    pit.enter_mandatory(
      p_params => msg_params(
                    msg_param('p_command', p_command),
                    msg_param('p_ftp_server', p_ftp_server)));
                    
    auto_login(p_ftp_server);

    -- Execute command locally as this method retrieves data via control connection
    -- Plus, result shall be immediately piped, so extracting it into a helper does not save code
    l_result := UTL_TCP.write_text(
                  g_server.control_connection,
                  l_command || utl_tcp.crlf,
                  length(l_command || utl_tcp.crlf));
    while utl_tcp.available(g_server.control_connection, g_timeout) > 0 loop
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
      logout;
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end get_help;


  function list_directory(
    p_directory in varchar2 default null,
    p_ftp_server in varchar2 default null)
    return ftp_list_tab pipelined
  as
    l_data_reply ftp_reply_tab;
  begin
    pit.enter_mandatory(
      p_params => msg_params(
                    msg_param('p_directory', p_directory),
                    msg_param('p_ftp_server', p_ftp_server)));
                    
    auto_login(p_ftp_server);

    read_data(c_type_binary, c_ftp_list || p_directory, code_tab(150));
    l_data_reply := g_server.data_reply;
    if l_data_reply is not null then
      for i in l_data_reply.first .. l_data_reply.last loop
        pipe row (convert_directory_list(l_data_reply(i).message));
      end loop;
    end if;

    auto_logout;
    
    pit.leave_mandatory;
    return;
  exception
    when others then
      logout;
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end list_directory;


  procedure create_directory(
    p_directory in varchar2,
    p_ftp_server in varchar2 default null)
  as
    l_ftp_server ftp_server_rec;
  begin
    pit.enter_mandatory(
      p_params => msg_params(
                    msg_param('p_directory', p_directory),
                    msg_param('p_ftp_server', p_ftp_server)));
                    
    auto_login(p_ftp_server);

    do_command(trim(c_ftp_make_directory || p_directory), code_tab(257));

    auto_logout;
    
    pit.leave_mandatory;
  exception
    when others then
      logout;
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end create_directory;


  procedure remove_directory(
    p_directory in varchar2,
    p_ftp_server in varchar2 default null)
  as
  begin
    pit.enter_mandatory(
      p_params => msg_params(
                    msg_param('p_directory', p_directory),
                    msg_param('p_ftp_server', p_ftp_server)));
                    
    auto_login(p_ftp_server);

    do_command(c_ftp_remove_directory || p_directory, code_tab(250));

    auto_logout;
    
    pit.leave_mandatory;
  exception
    when others then
      logout;
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end remove_directory;


  procedure rename_file(
    p_from in varchar2,
    p_to in varchar2,
    p_ftp_server in varchar2 default null)
  as
  begin
    pit.enter_mandatory(
      p_params => msg_params(
                    msg_param('p_from', p_from),
                    msg_param('p_to', p_to),
                    msg_param('p_ftp_server', p_ftp_server)));
                    
    auto_login(p_ftp_server);

    do_command(c_ftp_rename_from || p_from, code_tab(350));
    do_command(c_ftp_rename_to || p_to, code_tab(250));

    auto_logout;
    
    pit.leave_mandatory;
  exception
    when others then
      logout;
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end rename_file;


  procedure delete_file(
    p_file in varchar2,
    p_ftp_server in varchar2 default null)
  as
  begin
    pit.enter_mandatory(
      p_params => msg_params(
                    msg_param('p_file', p_file),
                    msg_param('p_ftp_server', p_ftp_server)));
                    
    auto_login(p_ftp_server);

    do_command(c_ftp_delete || p_file, code_tab(250));

    auto_logout;
    
    pit.leave_mandatory;
  exception
    when others then
      logout;
      pit.sql_exception(msg.SQL_ERROR, msg_args(sqlerrm));
  end delete_file;

begin
  initialize;
end utl_ftp;
/