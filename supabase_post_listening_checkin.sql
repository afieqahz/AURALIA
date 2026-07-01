alter table public.mood
  add column if not exists check_in_type text not null default 'beforeListening',
  add column if not exists playlist_name text,
  add column if not exists helpfulness text;

comment on column public.mood.check_in_type is
  'Distinguishes mood selection before music from the check-in after a playlist.';

comment on column public.mood.playlist_name is
  'The completed AURALIA playlist associated with an after-listening check-in.';

comment on column public.mood.helpfulness is
  'User response: yes, aLittle, or no.';
