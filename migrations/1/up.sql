CREATE TABLE node_type (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE monk (
    id           SERIAL PRIMARY KEY,
    username     VARCHAR(100) NOT NULL UNIQUE,
    is_anonymous BOOLEAN   DEFAULT FALSE,
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE EXTENSION IF NOT EXISTS ltree WITH SCHEMA public;

-- Table for storing user posts
CREATE TABLE node (
    id           BIGSERIAL PRIMARY KEY,
    node_type_id INTEGER NOT NULL REFERENCES node_type (id),
    author_id    INTEGER NOT NULL REFERENCES monk (id),
    title        VARCHAR(255) NOT NULL,
    doctext      TEXT         NOT NULL,
    reputation   INTEGER      NOT NULL DEFAULT 0,
    created_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Table for storing reply hierarchy information
CREATE TABLE note (
    node_id      BIGINT PRIMARY KEY REFERENCES node(id),
    parent_node  BIGINT NOT NULL REFERENCES node(id),
    root_node    BIGINT NOT NULL REFERENCES node(id),
    path         public.ltree  NOT NULL
);

-- Indexes for better query performance
CREATE INDEX idx_node_created ON node(created_at);
CREATE INDEX idx_node_author ON node(author_id);
CREATE INDEX idx_node_type ON node(node_type_id);

-- Indexes for note hierarchy
CREATE INDEX idx_note_root ON note(root_node);
CREATE INDEX idx_note_parent ON note(parent_node);
CREATE INDEX idx_note_path ON note USING GIST (path);

-- Insert the anonymous user
INSERT INTO monk (id, username, created_at, updated_at)
VALUES (961, 'Anonymous Monk', NOW(), NOW());

-- Add node types
INSERT INTO node_type (id, name) VALUES
(11, 'note'),
(115, 'perlquestion');

-- Function to update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_modified_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers to automatically update timestamps

CREATE TRIGGER update_node_modtime
BEFORE UPDATE ON node
FOR EACH ROW EXECUTE FUNCTION update_modified_column();

CREATE TRIGGER update_author_modtime
BEFORE UPDATE ON monk
FOR EACH ROW EXECUTE FUNCTION update_modified_column();
