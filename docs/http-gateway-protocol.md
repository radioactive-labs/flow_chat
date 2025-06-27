# FlowChat HTTP Gateway Protocol Specification

**Version:** 1.0  
**Date:** 2025-06-27  
**Status:** Stable

## Overview

The FlowChat HTTP Gateway Protocol defines a simple JSON-based request/response format for building conversational flows over HTTP. It enables any HTTP endpoint to participate in FlowChat's conversation framework with session management, media support, and interactive elements.

## Protocol Design

The protocol is designed to be:
- **Simple**: Easy to implement with any web framework
- **Stateless**: Each request contains all necessary context
- **Flexible**: Supports various response types and media
- **Extensible**: Can be enhanced without breaking compatibility

## Request Format

### HTTP Method
All requests use **POST** method.

### Headers
```
Content-Type: application/json
Accept: application/json
```

### Request Body
```json
{
  "session_id": "string",
  "user_id": "string", 
  "input": "string",
  "simulator_mode": boolean
}
```

#### Request Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `session_id` | string | Yes | Unique identifier for the conversation session |
| `user_id` | string | Yes | Unique identifier for the user (phone number, email, etc.) |
| `input` | string | Yes | User's input message (empty string for initial request) |
| `simulator_mode` | boolean | No | Indicates if request is from FlowChat simulator |

#### Example Request
```json
{
  "session_id": "sess_abc123",
  "user_id": "+256700123456",
  "input": "1",
  "simulator_mode": true
}
```

## Response Format

### HTTP Status Codes
- **200 OK**: Successful response with flow continuation
- **400 Bad Request**: Invalid request format
- **500 Internal Server Error**: Server processing error

### Response Body
```json
{
  "type": "string",
  "message": "string",
  "choices": "object|null",
  "media": "object|null"
}
```

#### Response Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | string | Yes | Response type: `prompt`, `text`, or `terminal` |
| `message` | string | Yes | Text message to display to user |
| `choices` | object | No | Interactive choices for user selection |
| `media` | object | No | Media content (images, videos, etc.) |

## Response Types

### 1. Prompt Response
Interactive response expecting user input with optional choices.

```json
{
  "type": "prompt",
  "message": "Welcome! Please choose an option:",
  "choices": {
    "1": "View Profile",
    "2": "Send Message",
    "3": "Settings"
  }
}
```

**Behavior**: Session continues, awaiting user input.

### 2. Text Response
Simple informational message.

```json
{
  "type": "text",
  "message": "Processing your request..."
}
```

**Behavior**: Session continues, awaiting user input.

### 3. Terminal Response
Final message that ends the conversation session.

```json
{
  "type": "terminal",
  "message": "Thank you for using our service. Goodbye!"
}
```

**Behavior**: Session ends, no further input expected.

## Choices Format

Choices enable interactive menu-driven flows. They can be provided in two formats:

### Simple Format
```json
{
  "choices": {
    "1": "Option One",
    "2": "Option Two",
    "3": "Option Three"
  }
}
```

### Object Format
```json
{
  "choices": {
    "choice1": {
      "key": "1",
      "value": "Option One"
    },
    "choice2": {
      "key": "2", 
      "value": "Option Two"
    }
  }
}
```

**Key Guidelines:**
- Keys should be simple (numbers, single letters)
- Values should be descriptive text
- Maximum 10 choices recommended for usability
- Empty choices object `{}` means free-form input expected

## Media Support

The protocol supports various media types in responses.

### Image Media
```json
{
  "media": {
    "type": "image",
    "url": "https://example.com/image.jpg",
    "caption": "Optional image caption"
  }
}
```

### Video Media
```json
{
  "media": {
    "type": "video", 
    "url": "https://example.com/video.mp4",
    "caption": "Optional video caption"
  }
}
```

### Document Media
```json
{
  "media": {
    "type": "document",
    "url": "https://example.com/document.pdf",
    "filename": "report.pdf",
    "caption": "Download the full report"
  }
}
```

### Audio Media
```json
{
  "media": {
    "type": "audio",
    "url": "https://example.com/audio.mp3",
    "caption": "Voice message"
  }
}
```

**Media Guidelines:**
- URLs must be publicly accessible
- HTTPS URLs recommended for security
- Include appropriate file extensions
- Captions are optional but recommended for accessibility

## Session Management

### Session Lifecycle
1. **Initialization**: First request has empty `input` field
2. **Continuation**: Subsequent requests include user input
3. **Termination**: Response with `type: "terminal"` ends session

### Session State
The protocol is stateless from HTTP perspective. Session state must be managed by the endpoint implementation using:
- Database storage
- In-memory cache
- External session stores
- Cookies/tokens (if supported)

### Session ID Format
- Must be unique across all sessions
- Recommended: UUID, random string, or timestamped identifier
- Length: 8-64 characters
- Characters: alphanumeric, hyphens, underscores

## Error Handling

### Client Errors (4xx)
```json
{
  "type": "terminal",
  "message": "Invalid request format. Please try again later."
}
```

### Server Errors (5xx)
```json
{
  "type": "terminal", 
  "message": "Service temporarily unavailable. Please try again later."
}
```

### Validation Errors
```json
{
  "type": "prompt",
  "message": "Invalid selection. Please choose from the available options:",
  "choices": {
    "1": "Option A",
    "2": "Option B"
  }
}
```

## Implementation Examples

### Basic Flow Handler
```ruby
def handle_http_webhook
  data = JSON.parse(request.body.read)
  
  session_id = data['session_id']
  user_id = data['user_id']
  input = data['input']
  
  response = case input.downcase.strip
  when '', 'start'
    {
      type: 'prompt',
      message: 'Welcome! What would you like to do?',
      choices: {
        '1' => 'View Account',
        '2' => 'Make Payment',
        '3' => 'Get Help'
      }
    }
  when '1'
    {
      type: 'text',
      message: "Account Balance: $150.00\nLast Transaction: -$25.00"
    }
  when '2'
    {
      type: 'prompt',
      message: 'Enter payment amount:',
      choices: {}
    }
  when '3'
    {
      type: 'terminal',
      message: 'For help, call 1-800-HELP or visit our website.'
    }
  else
    {
      type: 'prompt',
      message: 'Please select a valid option:',
      choices: {
        '1' => 'View Account',
        '2' => 'Make Payment', 
        '3' => 'Get Help'
      }
    }
  end
  
  render json: response
end
```

### With Media Support
```ruby
def handle_media_flow
  # ... input parsing ...
  
  case input
  when 'show_chart'
    {
      type: 'prompt',
      message: 'Here is your sales chart:',
      media: {
        type: 'image',
        url: generate_chart_url(user_id),
        caption: 'Monthly sales data'
      },
      choices: {
        '0' => 'Back to menu'
      }
    }
  end
end
```

## Security Considerations

### Input Validation
- Always validate and sanitize user input
- Check session_id format and existence
- Validate user_id against expected format
- Limit input length to prevent abuse

### Authentication
- Implement endpoint authentication if needed
- Validate session ownership
- Use HTTPS for sensitive data
- Consider rate limiting

### Data Protection
- Don't log sensitive user input
- Encrypt session data if stored
- Use secure session identifiers
- Implement proper CORS headers

## Best Practices

### Response Design
1. **Keep messages concise** - Users prefer short, clear text
2. **Limit choices** - Maximum 5-7 options for better UX
3. **Use clear labels** - Make choice text descriptive
4. **Provide fallbacks** - Handle invalid input gracefully
5. **End flows properly** - Always provide terminal responses

### Session Management
1. **Set timeouts** - Expire inactive sessions
2. **Clean up data** - Remove old session data
3. **Handle duplicates** - Manage duplicate session IDs
4. **Log activities** - Track session flow for debugging

### Error Handling
1. **Fail gracefully** - Provide helpful error messages
2. **Log errors** - Capture errors for debugging
3. **Retry logic** - Handle temporary failures
4. **Fallback flows** - Provide alternative paths

## Protocol Extensions

### Custom Fields
Implementations may include additional fields in requests/responses:

```json
{
  "type": "prompt",
  "message": "Hello!",
  "choices": {...},
  "metadata": {
    "flow_version": "1.2",
    "user_lang": "en"
  }
}
```

### Future Enhancements
- Rich media support (carousels, buttons)
- Location sharing
- File uploads
- Real-time messaging
- Multi-turn conversations

## Compliance

### HTTP Standards
- Follows HTTP/1.1 and HTTP/2 specifications
- Uses standard status codes and headers
- Supports CORS for cross-origin requests

### JSON Standards
- Follows RFC 7159 JSON specification
- Uses UTF-8 encoding
- Validates JSON schema on input

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-06-27 | Initial specification |

---

For implementation questions or protocol clarifications, please refer to the FlowChat documentation or contact the development team. 