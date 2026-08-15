import CardCopilotStore
import MapKit

func predict(poiCategory: MKPointOfInterestCategory?, merchantName: String) -> CategoryPrediction {
    CardCopilotStore.predict(poiCategoryRaw: poiCategory?.rawValue, merchantName: merchantName)
}
