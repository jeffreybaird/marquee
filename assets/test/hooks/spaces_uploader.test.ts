import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import SpacesUploader from "../../js/hooks/spaces_uploader"
import { html, mountHook } from "../support/mount"
import { FakeXMLHttpRequest } from "../support/xhr"

function uploader(kind = "series_cover", targetId?: string) {
  const target = targetId === undefined ? "" : `data-target-id="${targetId}"`
  const el = html(`
    <div id="cover-upload" data-upload-kind="${kind}" ${target}>
      <input type="file" />
    </div>
  `)
  const mounted = mountHook(SpacesUploader, el)
  const input = el.querySelector<HTMLInputElement>("input")!
  return { ...mounted, el, input }
}

function pick(input: HTMLInputElement, file: File) {
  Object.defineProperty(input, "files", { value: [file], configurable: true })
  input.dispatchEvent(new Event("change"))
}

const ready = (overrides: Record<string, unknown> = {}) => ({
  kind: "series_cover",
  target_id: null,
  presigned_url: "https://spaces/put",
  public_url: "https://cdn/cover.png",
  key: "org/cover.png",
  headers: { "Content-Type": "image/png", "x-amz-acl": "public-read" },
  ...overrides,
})

const flush = () => new Promise<void>((resolve) => setTimeout(resolve, 0))

describe("SpacesUploader", () => {
  beforeEach(() => {
    FakeXMLHttpRequest.install()
  })

  afterEach(() => {
    vi.unstubAllGlobals()
    document.body.innerHTML = ""
  })

  it("asks the server for a presigned URL when a file is picked", () => {
    const { input, pushEvent } = uploader("series_cover", "slot-1")

    pick(input, new File(["png"], "cover.png", { type: "image/png" }))

    expect(pushEvent).toHaveBeenCalledWith("spaces_presign_requested", {
      kind: "series_cover",
      target_id: "slot-1",
      filename: "cover.png",
      content_type: "image/png",
      size: 3,
    })
  })

  it("defaults the content type when the browser reports none", () => {
    const { input, pushEvent } = uploader()

    pick(input, new File(["x"], "blob"))

    expect(pushEvent).toHaveBeenCalledWith(
      "spaces_presign_requested",
      expect.objectContaining({ content_type: "application/octet-stream", target_id: null }),
    )
  })

  it("PUTs the file to the presigned URL with the given headers and reports completion", async () => {
    const { input, pushEvent, serverPush } = uploader()
    const file = new File(["png"], "cover.png", { type: "image/png" })
    pick(input, file)

    serverPush("spaces_presign_ready", ready())

    const xhr = FakeXMLHttpRequest.latest()
    expect(xhr.method).toBe("PUT")
    expect(xhr.url).toBe("https://spaces/put")
    expect(xhr.headers).toEqual({ "Content-Type": "image/png", "x-amz-acl": "public-read" })
    expect(xhr.body).toBe(file)

    xhr.progress(30, 100)
    expect(pushEvent).toHaveBeenCalledWith("spaces_upload_progress", {
      kind: "series_cover",
      target_id: null,
      percent: 30,
    })

    xhr.respond(200)
    await flush()
    expect(pushEvent).toHaveBeenCalledWith("spaces_upload_complete", {
      kind: "series_cover",
      target_id: null,
      public_url: "https://cdn/cover.png",
      key: "org/cover.png",
      duration_ms: expect.any(Number),
      filename: "cover.png",
      content_type: "image/png",
      size: 3,
    })
  })

  it("ignores presign replies for a different kind or target", () => {
    const { input, serverPush } = uploader("series_cover", "slot-1")
    pick(input, new File(["png"], "cover.png"))

    serverPush("spaces_presign_ready", ready({ kind: "season_cover", target_id: "slot-1" }))
    serverPush("spaces_presign_ready", ready({ target_id: "slot-2" }))

    expect(FakeXMLHttpRequest.instances).toHaveLength(0)
  })

  it("ignores a presign reply when no file is pending", () => {
    const { serverPush } = uploader()

    serverPush("spaces_presign_ready", ready())

    expect(FakeXMLHttpRequest.instances).toHaveLength(0)
  })

  it("reports HTTP failures with a truncated response body", async () => {
    const { input, pushEvent, serverPush } = uploader()
    pick(input, new File(["png"], "cover.png", { type: "image/png" }))
    serverPush("spaces_presign_ready", ready())

    const xhr = FakeXMLHttpRequest.latest()
    xhr.progress(40, 100)
    xhr.respond(403, "x".repeat(2000))
    await flush()

    expect(pushEvent).toHaveBeenCalledWith(
      "spaces_upload_error",
      expect.objectContaining({
        kind: "series_cover",
        key: "org/cover.png",
        filename: "cover.png",
        error: "Upload failed with status 403",
        http_status: 403,
        response_body: "x".repeat(1024),
        bytes_uploaded: 40,
        duration_ms: expect.any(Number),
      }),
    )
  })

  it.each([
    ["network", (xhr: FakeXMLHttpRequest) => xhr.fail(), "Network error during upload"],
    ["timeout", (xhr: FakeXMLHttpRequest) => xhr.timeout(), "Upload timed out"],
    ["abort", (xhr: FakeXMLHttpRequest) => xhr.abort(), "Upload aborted"],
  ])("reports a %s failure", async (_name, trigger, message) => {
    const { input, pushEvent, serverPush } = uploader()
    pick(input, new File(["png"], "cover.png"))
    serverPush("spaces_presign_ready", ready())

    trigger(FakeXMLHttpRequest.latest())
    await flush()

    expect(pushEvent).toHaveBeenCalledWith(
      "spaces_upload_error",
      expect.objectContaining({ error: message, response_body: null }),
    )
  })

  it("skips headers the browser refuses to set", () => {
    const { input, serverPush } = uploader()
    pick(input, new File(["png"], "cover.png"))

    // The double is constructed inside the hook, so pre-configure the class.
    const rejecting = class extends FakeXMLHttpRequest {
      constructor() {
        super()
        this.rejectHeaders.add("Host")
      }
    }
    vi.stubGlobal("XMLHttpRequest", rejecting)

    serverPush("spaces_presign_ready", ready({ headers: { Host: "spaces", "x-ok": "1" } }))

    expect(FakeXMLHttpRequest.latest().headers).toEqual({ "x-ok": "1" })
  })

  it("aborts an in-flight upload when destroyed", () => {
    const { input, hook, serverPush } = uploader()
    pick(input, new File(["png"], "cover.png"))
    serverPush("spaces_presign_ready", ready())

    hook.destroyed()

    expect(FakeXMLHttpRequest.latest().aborted).toBe(true)
  })

  it("does nothing without a file input", () => {
    const el = html(`<div id="no-input" data-upload-kind="x"></div>`)
    const { handledEvents } = mountHook(SpacesUploader, el)

    expect(handledEvents()).toEqual([])
  })
})
