-- calendar_fresh_db-create.sql
-- Schema-only DDL for calendar_fresh_db. Database must already exist.
-- Run as: psql -U henninb calendar_fresh_db < calendar_fresh_db-create.sql

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

-- Enum types

CREATE TYPE public.occurrencestatus AS ENUM (
    'upcoming',
    'completed',
    'skipped',
    'overdue'
);

CREATE TYPE public.priority AS ENUM (
    'low',
    'medium',
    'high'
);

CREATE TYPE public.taskrecurrence AS ENUM (
    'none',
    'daily',
    'weekly',
    'biweekly',
    'monthly',
    'yearly'
);

CREATE TYPE public.taskstatus AS ENUM (
    'todo',
    'in_progress',
    'done',
    'cancelled'
);

CREATE TYPE public.weekendshift AS ENUM (
    'back',
    'forward',
    'back_sat_only',
    'nearest'
);

-- Tables

CREATE TABLE public.categories (
    id integer NOT NULL,
    name character varying(50) NOT NULL,
    color character varying(7),
    icon character varying(10),
    description text,
    is_seeded boolean DEFAULT false
);

CREATE SEQUENCE public.categories_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.categories_id_seq OWNED BY public.categories.id;
ALTER TABLE ONLY public.categories ALTER COLUMN id SET DEFAULT nextval('public.categories_id_seq'::regclass);

CREATE TABLE public.credit_cards (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    issuer character varying(100),
    last_four character varying(4),
    statement_close_day integer,
    grace_period_days integer,
    weekend_shift public.weekendshift,
    cycle_days integer,
    cycle_reference_date date,
    due_day_same_month integer,
    due_day_next_month integer,
    annual_fee_month integer,
    is_active boolean,
    created_at timestamp without time zone,
    is_seeded boolean DEFAULT false
);

CREATE SEQUENCE public.credit_cards_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.credit_cards_id_seq OWNED BY public.credit_cards.id;
ALTER TABLE ONLY public.credit_cards ALTER COLUMN id SET DEFAULT nextval('public.credit_cards_id_seq'::regclass);

CREATE TABLE public.persons (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    email character varying(200)
);

CREATE SEQUENCE public.persons_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.persons_id_seq OWNED BY public.persons.id;
ALTER TABLE ONLY public.persons ALTER COLUMN id SET DEFAULT nextval('public.persons_id_seq'::regclass);

CREATE TABLE public.events (
    id integer NOT NULL,
    title character varying(200) NOT NULL,
    category_id integer NOT NULL,
    credit_card_id integer,
    rrule text,
    dtstart date NOT NULL,
    dtend_rule date,
    duration_days integer,
    description text,
    location character varying(300),
    reminder_days json,
    priority public.priority,
    amount numeric(10,2),
    is_active boolean,
    generates_tasks boolean DEFAULT false NOT NULL,
    gcal_calendar_id character varying(200),
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    is_seeded boolean DEFAULT false
);

CREATE SEQUENCE public.events_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.events_id_seq OWNED BY public.events.id;
ALTER TABLE ONLY public.events ALTER COLUMN id SET DEFAULT nextval('public.events_id_seq'::regclass);

CREATE TABLE public.occurrences (
    id integer NOT NULL,
    event_id integer NOT NULL,
    occurrence_date date NOT NULL,
    status public.occurrencestatus,
    notes text,
    gcal_event_id character varying(200),
    synced_at timestamp without time zone,
    created_at timestamp without time zone
);

CREATE SEQUENCE public.occurrences_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.occurrences_id_seq OWNED BY public.occurrences.id;
ALTER TABLE ONLY public.occurrences ALTER COLUMN id SET DEFAULT nextval('public.occurrences_id_seq'::regclass);

CREATE TABLE public.tasks (
    id integer NOT NULL,
    occurrence_id integer,
    category_id integer,
    title character varying(200) NOT NULL,
    description text,
    status public.taskstatus,
    priority public.priority,
    assignee_id integer,
    due_date date,
    estimated_minutes integer,
    recurrence character varying DEFAULT 'none'::character varying NOT NULL,
    "order" integer DEFAULT 0 NOT NULL,
    gtask_id character varying(200),
    synced_at timestamp without time zone,
    parent_task_id integer,
    completed_at timestamp without time zone,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);

CREATE SEQUENCE public.tasks_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.tasks_id_seq OWNED BY public.tasks.id;
ALTER TABLE ONLY public.tasks ALTER COLUMN id SET DEFAULT nextval('public.tasks_id_seq'::regclass);

CREATE TABLE public.subtasks (
    id integer NOT NULL,
    task_id integer NOT NULL,
    title character varying(200) NOT NULL,
    status public.taskstatus,
    due_date date,
    "order" integer,
    gtask_id character varying,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    completed_at timestamp with time zone
);

CREATE SEQUENCE public.subtasks_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.subtasks_id_seq OWNED BY public.subtasks.id;
ALTER TABLE ONLY public.subtasks ALTER COLUMN id SET DEFAULT nextval('public.subtasks_id_seq'::regclass);

-- Primary keys and unique constraints

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_name_key UNIQUE (name);

ALTER TABLE ONLY public.credit_cards
    ADD CONSTRAINT credit_cards_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.persons
    ADD CONSTRAINT persons_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.occurrences
    ADD CONSTRAINT occurrences_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.occurrences
    ADD CONSTRAINT uq_event_occurrence_date UNIQUE (event_id, occurrence_date);

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.subtasks
    ADD CONSTRAINT subtasks_pkey PRIMARY KEY (id);

-- Indexes

CREATE INDEX ix_categories_id ON public.categories USING btree (id);
CREATE INDEX ix_credit_cards_id ON public.credit_cards USING btree (id);
CREATE INDEX ix_persons_id ON public.persons USING btree (id);
CREATE INDEX ix_events_id ON public.events USING btree (id);
CREATE INDEX ix_occurrences_id ON public.occurrences USING btree (id);
CREATE INDEX ix_occurrences_occurrence_date ON public.occurrences USING btree (occurrence_date);
CREATE INDEX ix_tasks_id ON public.tasks USING btree (id);
CREATE INDEX ix_subtasks_id ON public.subtasks USING btree (id);

-- Foreign key constraints

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id);

ALTER TABLE ONLY public.occurrences
    ADD CONSTRAINT occurrences_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_occurrence_id_fkey FOREIGN KEY (occurrence_id) REFERENCES public.occurrences(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_assignee_id_fkey FOREIGN KEY (assignee_id) REFERENCES public.persons(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_parent_task_id_fkey FOREIGN KEY (parent_task_id) REFERENCES public.tasks(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.subtasks
    ADD CONSTRAINT subtasks_task_id_fkey FOREIGN KEY (task_id) REFERENCES public.tasks(id) ON DELETE CASCADE;

GRANT ALL ON SCHEMA public TO henninb;
