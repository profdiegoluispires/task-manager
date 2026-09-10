resource "google_storage_bucket" "b" {
  name     = "meu-bucket-residencia-tech"
  location = "US"
  project  = "residencia-tech-gcp"
}