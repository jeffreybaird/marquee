/**
 * MuxUploader hook
 *
 * Handles direct video upload from browser to Mux.
 * Video bytes never touch Bobine's servers.
 *
 * This hook lives on a persistent element outside the upload modal.
 * It captures the selected file when it changes, so the file reference
 * survives the modal re-render that happens on form submit.
 *
 * Events received from server:
 *   - "start_upload" { upload_url: string, video_id: string }
 *
 * Events sent to server:
 *   - "upload_progress" { video_id: string, percent: number }
 *   - "upload_complete" { video_id: string }
 *   - "upload_error"    { video_id: string, error: string }
 */
const MuxUploader = {
  mounted() {
    this.selectedFile = null as File | null

    // Listen for file selection anywhere in the document
    // (the file input is in the modal which may re-render)
    document.addEventListener("change", (e: Event) => {
      const target = e.target as HTMLInputElement
      if (target?.getAttribute("data-test") === "upload-file" && target.files?.[0]) {
        this.selectedFile = target.files[0]
      }
    })

    this.handleEvent("start_upload", ({ upload_url, video_id }: { upload_url: string; video_id: string }) => {
      if (!this.selectedFile) {
        this.pushEvent("upload_error", { video_id, error: "No file selected" })
        return
      }

      this.uploadToMux(upload_url, this.selectedFile, video_id)
      this.selectedFile = null
    })
  },

  async uploadToMux(url: string, file: File, videoId: string) {
    try {
      const xhr = new XMLHttpRequest()
      this.currentXhr = xhr

      xhr.upload.addEventListener("progress", (e: ProgressEvent) => {
        if (e.lengthComputable) {
          const percent = Math.round((e.loaded / e.total) * 100)
          this.pushEvent("upload_progress", { video_id: videoId, percent })
        }
      })

      xhr.addEventListener("load", () => {
        if (xhr.status >= 200 && xhr.status < 300) {
          this.pushEvent("upload_complete", { video_id: videoId })
        } else {
          this.pushEvent("upload_error", {
            video_id: videoId,
            error: `Upload failed with status ${xhr.status}`,
          })
        }
      })

      xhr.addEventListener("error", () => {
        this.pushEvent("upload_error", {
          video_id: videoId,
          error: "Network error during upload",
        })
      })

      xhr.open("PUT", url)
      xhr.send(file)
    } catch (error) {
      this.pushEvent("upload_error", {
        video_id: videoId,
        error: String(error),
      })
    }
  },

  destroyed() {
    if (this.currentXhr) {
      this.currentXhr.abort()
    }
  },
}

export default MuxUploader
