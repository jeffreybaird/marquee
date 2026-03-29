/**
 * MuxUploader hook
 *
 * Handles direct video upload from browser to Mux.
 * Video bytes never touch Bobine's servers.
 *
 * This hook lives on a persistent element outside the upload modal
 * so it survives modal open/close cycles.
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
    this.handleEvent("start_upload", ({ upload_url, video_id }: { upload_url: string; video_id: string }) => {
      // Find the file input in the upload modal form
      const fileInput = document.querySelector("[data-test='upload-file']") as HTMLInputElement
      const file = fileInput?.files?.[0]
      if (!file) {
        this.pushEvent("upload_error", { video_id, error: "No file selected" })
        return
      }

      this.uploadToMux(upload_url, file, video_id)
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
