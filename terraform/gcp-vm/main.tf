# Necessário: gcloud auth application-default login --no-browser

resource "google_compute_instance" "vm" {
  name         = "minha-vm"
  machine_type = "e2-micro"
  zone         = "us-central1-a"
  project      = "residencia-tech-gcp"

  boot_disk {
    initialize_params { image = "debian-cloud/debian-12" }
  }

  network_interface {
    network       = "default"
    access_config {}   # necessário para a VM receber um IP público
  }
}