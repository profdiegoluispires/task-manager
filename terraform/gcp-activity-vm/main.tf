resource "google_compute_instance" "task_manager_vm" {
  name         = "task-manager-vm"
  machine_type = "e2-micro"
  zone         = "us-central1-a"
  project      = "residencia-tech-gcp"

  boot_disk {
    initialize_params { image = "debian-cloud/debian-12" }
  }

  network_interface {
    network       = "default"
    access_config {}
  }

  tags = ["task-manager"]

  # Executado automaticamente pelo Compute Engine assim que a VM sobe —
  # dispensa SSH manual para instalar e iniciar a aplicação.
  metadata_startup_script = file("${path.module}/../../scripts/deploy-vm.sh")
}

resource "google_compute_firewall" "allow_http" {
  name          = "allow-task-manager-http"
  network       = "default"
  project       = "residencia-tech-gcp"
  allow {
    protocol = "tcp"
    ports    = ["3000"]
  }
  target_tags   = ["task-manager"]
  source_ranges = ["0.0.0.0/0"]
}