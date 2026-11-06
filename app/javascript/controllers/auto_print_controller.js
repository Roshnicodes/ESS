import { Controller } from "@hotwired/stimulus"

// Opens the print dialog once the page has drawn (used after "Under process & Print").
export default class extends Controller {
  connect() { setTimeout(() => window.print(), 600) }
}
