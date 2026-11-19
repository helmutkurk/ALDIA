"""Shared report selection for public read endpoints."""

from sqlalchemy import Select, select

from app.models import Report
from app.schemas import ReadFilters, parse_bbox


def report_query(filters: ReadFilters) -> Select[tuple[Report]]:
    query = select(Report)
    if filters.category is not None:
        query = query.where(Report.category == filters.category)
    if filters.status is not None:
        query = query.where(Report.status == filters.status)
    if filters.resolution is not None:
        query = query.where(Report.resolution == filters.resolution)
    if filters.bbox is not None:
        west, south, east, north = parse_bbox(filters.bbox)
        query = query.where(
            Report.longitude.between(west, east), Report.latitude.between(south, north)
        )
    return query
