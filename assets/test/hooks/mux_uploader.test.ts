import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import MuxUploader from "../../js/hooks/mux_uploader"
import { html, mountHook } from "../support/mount"
import { FakeXMLHttpRequest } from "../support/xhr"

const file = (name: string) => new File(["bytes"], name, { type: "video/mp4" })

function selectFiles(...files: File[]) {
  const input = html<HTMLInputElement>(`<input type="file" data-test="upload-file" />`)
  Object.defineProperty(input, "files", { value: files, configurable: true })
  document.body.appendChild(input)
  input.dispatchEvent(new Event("change", { bubbles: true }))
  return input
}

const flush = () => new Promise<void>((resolve) => setTimeout(resolve, 0))

describe("MuxUploader", () => {
  beforeEach(() => {
    FakeXMLHttpRequest.install()
  })

  afterEach(() => {
    vi.unstubAllGlobals()
    document.body.innerHTML = ""
  })

  it("assigns client ids to selected files and reports them", () => {
    const { pushEvent } = mountHook(MuxUploader, html(`<div id="uploader"></div>`))

    selectFiles(file("a.mp4"), file("b.mp4"))

    expect(pushEvent).toHaveBeenCalledWith("files_selected", {
      files: [
        { client_id: "file_1", name: "a.mp4" },
        { client_id: "file_2", name: "b.mp4" },
      ],
    })
  })

  it("ignores change events from other inputs", () => {
    const { pushEvent } = mountHook(MuxUploader, html(`<div id="uploader"></div>`))
    const other = html<HTMLInputElement>(`<input type="file" />`)
    Object.defineProperty(other, "files", { value: [file("a.mp4")] })
    document.body.appendChild(other)

    other.dispatchEvent(new Event("change", { bubbles: true }))

    expect(pushEvent).not.toHaveBeenCalled()
  })

  it("uploads a multi-file queue sequentially, matching files by client id", async () => {
    const { pushEvent, serverPush } = mountHook(MuxUploader, html(`<div id="uploader"></div>`))
    const [a, b] = [file("a.mp4"), file("b.mp4")]
    selectFiles(a, b)

    serverPush("start_multi_upload", {
      queue: [
        { client_id: "file_2", video_id: "vid-b", upload_url: "https://mux/b" },
        { client_id: "file_1", video_id: "vid-a", upload_url: "https://mux/a" },
      ],
    })

    expect(FakeXMLHttpRequest.instances).toHaveLength(1)
    const first = FakeXMLHttpRequest.latest()
    expect(first.method).toBe("PUT")
    expect(first.url).toBe("https://mux/b")
    expect(first.body).toBe(b)

    first.progress(50, 100)
    expect(pushEvent).toHaveBeenCalledWith("upload_progress", { video_id: "vid-b", percent: 50 })

    first.respond(200)
    await flush()
    expect(pushEvent).toHaveBeenCalledWith("upload_complete", { video_id: "vid-b" })

    expect(FakeXMLHttpRequest.instances).toHaveLength(2)
    const second = FakeXMLHttpRequest.latest()
    expect(second.url).toBe("https://mux/a")
    expect(second.body).toBe(a)
  })

  it("reports a missing file and moves on to the next entry", async () => {
    const { pushEvent, serverPush } = mountHook(MuxUploader, html(`<div id="uploader"></div>`))
    selectFiles(file("a.mp4"))

    serverPush("start_multi_upload", {
      queue: [
        { client_id: "file_99", video_id: "gone", upload_url: "https://mux/gone" },
        { client_id: "file_1", video_id: "vid-a", upload_url: "https://mux/a" },
      ],
    })
    await flush()

    expect(pushEvent).toHaveBeenCalledWith("upload_error", {
      video_id: "gone",
      error: "File no longer available",
    })
    expect(FakeXMLHttpRequest.latest().url).toBe("https://mux/a")
  })

  it("reports HTTP and network failures per video", async () => {
    const { pushEvent, serverPush } = mountHook(MuxUploader, html(`<div id="uploader"></div>`))
    selectFiles(file("a.mp4"), file("b.mp4"))

    serverPush("start_multi_upload", {
      queue: [
        { client_id: "file_1", video_id: "vid-a", upload_url: "https://mux/a" },
        { client_id: "file_2", video_id: "vid-b", upload_url: "https://mux/b" },
      ],
    })

    FakeXMLHttpRequest.latest().respond(500)
    await flush()
    expect(pushEvent).toHaveBeenCalledWith("upload_error", {
      video_id: "vid-a",
      error: "Upload failed with status 500",
    })

    FakeXMLHttpRequest.latest().fail()
    await flush()
    expect(pushEvent).toHaveBeenCalledWith("upload_error", {
      video_id: "vid-b",
      error: "Network error during upload",
    })
  })

  it("supports the legacy single-file event and errors when nothing was selected", () => {
    const { pushEvent, serverPush } = mountHook(MuxUploader, html(`<div id="uploader"></div>`))

    serverPush("start_upload", { upload_url: "https://mux/x", video_id: "vid-x" })
    expect(pushEvent).toHaveBeenCalledWith("upload_error", {
      video_id: "vid-x",
      error: "No file selected",
    })

    const a = file("a.mp4")
    selectFiles(a)
    serverPush("start_upload", { upload_url: "https://mux/a", video_id: "vid-a" })
    expect(FakeXMLHttpRequest.latest().body).toBe(a)
  })

  it("aborts an in-flight upload when destroyed", () => {
    const { hook, serverPush } = mountHook(MuxUploader, html(`<div id="uploader"></div>`))
    selectFiles(file("a.mp4"))
    serverPush("start_multi_upload", {
      queue: [{ client_id: "file_1", video_id: "vid-a", upload_url: "https://mux/a" }],
    })

    hook.destroyed()

    expect(FakeXMLHttpRequest.latest().aborted).toBe(true)
  })
})
