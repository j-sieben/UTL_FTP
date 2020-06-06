begin

  pit_admin.merge_message_group(
    p_pmg_name => 'UTL_FTP',
    p_pmg_description => q'^Messages for UTL_FTP package^');
  
  pit_admin.merge_message(
    p_pms_name => 'FTP_TRANSIENT_ERROR',
	p_pms_pmg_name => 'UTL_FTP',
    p_pms_text => 'Ein temporärer Fehler wurde ausgelöst: #1#',
    p_pms_description => q'^Transiente Fehler sind Fehler, die vorübergehend auftreten. Probieren Sie es später noch einmal^',
    p_pms_pml_name => 'GERMAN',
    p_pms_pse_id => 30);
    
  pit_admin.merge_message(
    p_pms_name => 'FTP_PERMANENT_ERROR',
	p_pms_pmg_name => 'UTL_FTP',
    p_pms_text => 'Ein permanenter Fehler wurde ausgelöst: #1#',
    p_pms_pml_name => 'GERMAN',
    p_pms_pse_id => 20);
    
  pit_admin.merge_message(
    p_pms_name => 'FTP_RESPONSE_RECEIVED',
	p_pms_pmg_name => 'UTL_FTP',
    p_pms_text => 'Antwort: #1# #2#',
    p_pms_pml_name => 'GERMAN',
    p_pms_pse_id => 60);
    
  pit_admin.merge_message(
    p_pms_name => 'FTP_FILE_READ',
	p_pms_pmg_name => 'UTL_FTP',
    p_pms_text => 'Datei [#1#] #2# erfolgreich geöffnet. Größe: #3#',
    p_pms_pml_name => 'GERMAN',
    p_pms_pse_id => 60);
    
  pit_admin.merge_message(
    p_pms_name => 'FTP_RESPONSE_EXPECTED',
	p_pms_pmg_name => 'UTL_FTP',
    p_pms_text => 'OK',
    p_pms_pml_name => 'GERMAN',
    p_pms_pse_id => 70);
    
  pit_admin.merge_message(
    p_pms_name => 'FTP_UNEXPECTED_RESPONSE',
	p_pms_pmg_name => 'UTL_FTP',
    p_pms_text => 'Unerwartete Antwort erhalten: #1# #2#',
    p_pms_pml_name => 'GERMAN',
    p_pms_pse_id => 50);
    
  pit_admin.merge_message(
    p_pms_name => 'FTP_NO_RESPONSE',
	p_pms_pmg_name => 'UTL_FTP',
    p_pms_text => 'Der Befehl #1# lieferte keine Antwort. Das Warten hierauf könnte unnötig sein.',
    p_pms_pml_name => 'GERMAN',
    p_pms_pse_id => 20);
    
  pit_admin.merge_message(
    p_pms_name => 'FTP_INVALID_SERVER',
	p_pms_pmg_name => 'UTL_FTP',
    p_pms_text => 'Der FTP-Server #1# existiert nicht. Bitte registrieren Sie den Server.',
    p_pms_pml_name => 'GERMAN',
    p_pms_pse_id => 20);
    
  pit_admin.merge_message(
    p_pms_name => 'FTP_FILE_SENT',
	p_pms_pmg_name => 'UTL_FTP',
    p_pms_text => 'Datei vollständig gesendet',
    p_pms_pml_name => 'GERMAN',
    p_pms_pse_id => 50);
    
  pit_admin.merge_message(
    p_pms_name => 'FTP_FILE_RECEIVED',
	p_pms_pmg_name => 'UTL_FTP',
    p_pms_text => 'Datei vollständig gelesen',
    p_pms_pml_name => 'GERMAN',
    p_pms_pse_id => 50);
    
  pit_admin.merge_message(
    p_pms_name => 'FTP_NO_PAYLOAD',
	p_pms_pmg_name => 'UTL_FTP',
    p_pms_text => 'Keine Daten zur Übermittlung bereitgestellt. Verarbeitung wird abgebrochen.',
    p_pms_pml_name => 'GERMAN',
    p_pms_pse_id => 20);
    
  pit_admin.merge_message(
    p_pms_name => 'FTP_INVALID_SERVER_NAME',
	p_pms_pmg_name => 'UTL_FTP',
    p_pms_text => 'Der Name des Servers darf höchstens 30 Zeichen umfassen.',
    p_pms_pml_name => 'GERMAN',
    p_pms_pse_id => 30);
    
  pit_admin.merge_message(
    p_pms_name => 'FTP_MAX_TIMEOUT',
	p_pms_pmg_name => 'UTL_FTP',
    p_pms_text => 'Die Länge des Timeouts muss zwischen 0,1 und 30 Sekunden liegen.',
    p_pms_pml_name => 'GERMAN',
    p_pms_pse_id => 30);
    
   pit_admin.merge_message(
    p_pms_name => 'FTP_ERROR',
	p_pms_pmg_name => 'UTL_FTP',
    p_pms_text => 'Ein Fehler trat bei der FTP-Verarbeitung auf: #1#',
    p_pms_pml_name => 'GERMAN',
    p_pms_pse_id => 30);
    
  pit_admin.create_message_package;
end;
/
