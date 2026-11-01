-- Migration applied to Supabase: resource portrait paths and secure setter.
-- This file documents the schema change; the full SQL follows.
alter table public.resources add column if not exists photo_path text;
