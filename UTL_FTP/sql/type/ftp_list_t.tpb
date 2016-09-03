create or replace type body ftp_list_t as

  constructor function ftp_list_t
    return self as result as
  begin
    -- Empty constructor
    return;
  end ftp_list_t;

end;
/