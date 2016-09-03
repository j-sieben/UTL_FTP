begin
  
  pit_admin.merge_message(
    p_message_name => 'FTP_TRANSIENT_ERROR',
    p_message_text => 'A transient error has been raised: #1#',
    p_message_language => 'AMERICAN',
    p_severity => 30);
    
  pit_admin.translate_message(
    p_message_name => 'FTP_TRANSIENT_ERROR',
    p_message_text => 'Ein temporärer Fehler wurde ausgelöst: #1#',
    p_message_language => 'GERMAN');
    
  pit_admin.merge_message(
    p_message_name => 'FTP_PERMANENT_ERROR',
    p_message_text => 'A permanent error has been raised: #1#',
    p_message_language => 'AMERICAN',
    p_severity => 20);
    
  pit_admin.translate_message(
    p_message_name => 'FTP_PERMANENT_ERROR',
    p_message_text => 'Ein permanenter Fehler wurde ausgelöst: #1#',
    p_message_language => 'GERMAN');
    
  pit_admin.merge_message(
    p_message_name => 'FTP_RESPONSE_RECEIVED',
    p_message_text => 'Response: #1# #2#',
    p_message_language => 'AMERICAN',
    p_severity => 60);
    
  pit_admin.translate_message(
    p_message_name => 'FTP_RESPONSE_RECEIVED',
    p_message_text => 'Antwort: #1# #2#',
    p_message_language => 'GERMAN');
    
  pit_admin.merge_message(
    p_message_name => 'FTP_RESPONSE_EXPECTED',
    p_message_text => 'OK',
    p_message_language => 'AMERICAN',
    p_severity => 70);
    
  pit_admin.merge_message(
    p_message_name => 'FTP_UNEXPECTED_RESPONSE',
    p_message_text => 'Unexpected response received: #1# #2#',
    p_message_language => 'AMERICAN',
    p_severity => 50);
    
  pit_admin.translate_message(
    p_message_name => 'FTP_UNEXPECTED_RESPONSE',
    p_message_text => 'Unerwartete Antwort erhalten: #1# #2#',
    p_message_language => 'GERMAN');
    
  pit_admin.merge_message(
    p_message_name => 'FTP_NO_RESPONSE',
    p_message_text => 'Read reply for #1# did not create response. Call might be unnecessary.',
    p_message_language => 'AMERICAN',
    p_severity => 20);
    
  pit_admin.translate_message(
    p_message_name => 'FTP_NO_RESPONSE',
    p_message_text => 'Der Befehl #1# lieferte keine Antwort. Das Warten hierauf könnte unnötig sein.',
    p_message_language => 'GERMAN');
    
  pit_admin.merge_message(
    p_message_name => 'FTP_INVALID_SERVER',
    p_message_text => 'FTP-Server #1# does not exist. Please register server first.',
    p_message_language => 'AMERICAN',
    p_severity => 20);
    
  pit_admin.translate_message(
    p_message_name => 'FTP_INVALID_SERVER',
    p_message_text => 'Der FTP-Server #1# existiert nicht. Bitte registrieren Sie den Server.',
    p_message_language => 'GERMAN');
    
  pit_admin.merge_message(
    p_message_name => 'FTP_FILE_SENT',
    p_message_text => 'File sent completely',
    p_message_language => 'AMERICAN',
    p_severity => 50);
    
  pit_admin.translate_message(
    p_message_name => 'FTP_FILE_SENT',
    p_message_text => 'Datei vollständig gesendet',
    p_message_language => 'GERMAN');
    
  pit_admin.merge_message(
    p_message_name => 'FTP_FILE_RECEIVED',
    p_message_text => 'File read completely',
    p_message_language => 'AMERICAN',
    p_severity => 50);
    
  pit_admin.translate_message(
    p_message_name => 'FTP_FILE_RECEIVED',
    p_message_text => 'Datei vollständig gelesen',
    p_message_language => 'GERMAN');
    
  pit_admin.merge_message(
    p_message_name => 'FTP_NO_PAYLOAD',
    p_message_text => 'No data to transmit provided. Stopping process',
    p_message_language => 'AMERICAN',
    p_severity => 20);
    
  pit_admin.translate_message(
    p_message_name => 'FTP_NO_PAYLOAD',
    p_message_text => 'Keine Daten zur Übermittlung bereitgestellt. Verarbeitung wird abgebrochen.',
    p_message_language => 'GERMAN');
    
  pit_admin.create_message_package;
end;
/
