import { vi } from "vitest"

/**
 * Minimal XMLHttpRequest double for the direct-upload hooks. Records the
 * request and lets a test drive the outcome with `respond`, `fail`, etc.
 */
export class FakeXMLHttpRequest extends EventTarget {
  static instances: FakeXMLHttpRequest[] = []

  static install(): void {
    FakeXMLHttpRequest.instances = []
    vi.stubGlobal("XMLHttpRequest", FakeXMLHttpRequest)
  }

  static latest(): FakeXMLHttpRequest {
    const xhr = FakeXMLHttpRequest.instances[FakeXMLHttpRequest.instances.length - 1]
    if (!xhr) throw new Error("no XMLHttpRequest was created")
    return xhr
  }

  upload = new EventTarget()
  status = 0
  responseText = ""
  method = ""
  url = ""
  body: unknown = null
  headers: Record<string, string> = {}
  aborted = false
  /** Header names whose `setRequestHeader` call should throw, as browsers do for forbidden headers. */
  rejectHeaders = new Set<string>()

  constructor() {
    super()
    FakeXMLHttpRequest.instances.push(this)
  }

  open(method: string, url: string): void {
    this.method = method
    this.url = url
  }

  setRequestHeader(name: string, value: string): void {
    if (this.rejectHeaders.has(name)) throw new Error(`Refused to set unsafe header "${name}"`)
    this.headers[name] = value
  }

  send(body: unknown): void {
    this.body = body
  }

  abort(): void {
    this.aborted = true
    this.dispatchEvent(new Event("abort"))
  }

  progress(loaded: number, total: number): void {
    const event = new ProgressEvent("progress", { lengthComputable: true, loaded, total })
    this.upload.dispatchEvent(event)
  }

  respond(status: number, responseText = ""): void {
    this.status = status
    this.responseText = responseText
    this.dispatchEvent(new Event("load"))
  }

  fail(): void {
    this.dispatchEvent(new Event("error"))
  }

  timeout(): void {
    this.dispatchEvent(new Event("timeout"))
  }
}
