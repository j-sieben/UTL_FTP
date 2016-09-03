create or replace type ftp_reply_t is object(
  code number,
  message varchar2(4000)
) instantiable final;
/
