# Async and background processing

A webhook has a response deadline. If a flow does slow work (calling the platform API, hitting your own services) the webhook can time out and the platform will retry, sometimes delivering the same message twice. Async processing acknowledges the webhook immediately and runs the flow in a background job.

This works on gateways with an outbound API (WhatsApp, Telegram, HTTP, Intercom), because the job can send the reply through that API afterward. USSD cannot use it: its protocol requires the answer in the webhook response itself.

## Enabling it

Call `use_async` in the processor. It has two forms.

Use a factory, and let FlowChat provide the job class:

```ruby
config.use_async(factory: :whatsapp)
```

Or use your own ActiveJob subclass, with optional job params:

```ruby
config.use_async(MyFlowJob, deployment_id: 123)
```

The `factory:` form is the common one and needs no custom job class. See [factory-pattern.md](factory-pattern.md).

## How it works

The `GatewayAsyncSupport` concern, mixed into every async-capable gateway, does the detection and enqueueing.

1. On a real webhook, the gateway calls `should_enqueue_async?`. It returns true when async is enabled, the gateway supports it (`async_supported?`), and the request is not already running in the background.
2. If so, the gateway serializes the request (params, method, headers, host, path, body, remote ip) and enqueues the job with `perform_later(request_context: ..., **job_params)`, then returns an immediate acknowledgement to the platform.
3. The job reconstructs a `FlowChat::BackgroundController` from the serialized request. It quacks like a Rails controller (its `render` and `head` are no-ops, its `request` is a `BackgroundRequest` rebuilt from the serialized data), so the same gateway code runs against it.
4. Running in the background, `should_enqueue_async?` now returns false (the controller is a `BackgroundController`), so the gateway processes the flow inline and sends the reply through the platform API.

The same gateway and the same flow run in both passes. The only difference is who calls them: the webhook the first time, the job the second.

## Custom jobs

`FlowChat::AsyncJob` is the base class. It handles reconstructing the controller in `perform`; you implement `execute(controller, **job_params)`:

```ruby
class MyFlowJob < FlowChat::AsyncJob
  def execute(controller, **job_params)
    deployment_id = job_params[:deployment_id]
    processor = FlowChat::Processor.new(controller) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::CacheSessionStore
      config.use_async(MyFlowJob, deployment_id: deployment_id)
    end
    processor.run(WhatsAppFlow, :start)
  end
end
```

The job params you pass to `use_async` are forwarded to `execute`, so the background pass can rebuild the same processor. `FlowChat::GenericAsyncJob` is exactly this pattern wrapped around a factory, which is why the `factory:` form needs no job class of your own.

## ActiveJob is optional

`FlowChat::AsyncJob` subclasses `ActiveJob::Base` when ActiveJob is available. Without ActiveJob, FlowChat falls back to a plain class, so requiring the gem does not fail; you supply the queueing yourself in that case.

## Related

- [Factory pattern](factory-pattern.md)
- [Configuration](configuration.md#async-processing)
- [Architecture](architecture.md)
