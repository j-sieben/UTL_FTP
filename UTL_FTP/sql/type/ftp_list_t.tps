create or replace type ftp_list_t is object(
  item_id varchar2(100),
  item_name varchar2(2000),
  item_type varchar2(20),
  item_creation_date date,
  item_modify_date date,
  item_permission varchar2(10),
  file_size number,
  file_language varchar2(20),
  file_media_type varchar2(20),
  char_set varchar2(10),
  constructor function ftp_list_t
    return self as result
)instantiable final;
/