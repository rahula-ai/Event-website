// scripts/mongo-init.js
// Runs once when MongoDB container is first initialized.
// Creates a dedicated application user with least-privilege access.

db = db.getSiblingDB('dharmasthala_events');

// Create app-specific user (used by FastAPI backend)
db.createUser({
  user: process.env.MONGO_APP_USER || 'appuser',
  pwd:  process.env.MONGO_APP_PASS || 'changeme',
  roles: [{ role: 'readWrite', db: 'dharmasthala_events' }]
});

// Seed initial collections with schema validation
db.createCollection('contact_submissions', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['name', 'email', 'subject', 'message', 'created_at'],
      properties: {
        name:       { bsonType: 'string' },
        email:      { bsonType: 'string' },
        subject:    { bsonType: 'string' },
        message:    { bsonType: 'string' },
        created_at: { bsonType: 'string' }
      }
    }
  }
});

db.createCollection('newsletter_subscribers', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['email', 'subscribed_at'],
      properties: {
        email:         { bsonType: 'string' },
        subscribed_at: { bsonType: 'string' },
        active:        { bsonType: 'bool' }
      }
    }
  }
});

db.createCollection('event_registrations', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['event_id', 'event_title', 'name', 'email', 'created_at'],
      properties: {
        event_id:    { bsonType: 'int' },
        event_title: { bsonType: 'string' },
        name:        { bsonType: 'string' },
        email:       { bsonType: 'string' },
        guests:      { bsonType: 'int' },
        created_at:  { bsonType: 'string' }
      }
    }
  }
});

// Create indexes
db.contact_submissions.createIndex({ created_at: -1 });
db.newsletter_subscribers.createIndex({ email: 1 }, { unique: true });
db.event_registrations.createIndex({ event_id: 1, email: 1 });
db.event_registrations.createIndex({ created_at: -1 });

print('✅ MongoDB initialized: dharmasthala_events database ready');
